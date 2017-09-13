/* label handling */
ALTER TABLE planet_osm_polygon ADD COLUMN label_placement geometry(Geometry, 3857);
UPDATE planet_osm_polygon SET label_placement = ST_PointOnSurface(way);

CREATE OR REPLACE FUNCTION trigger_function_polygon()
RETURNS TRIGGER AS $$
BEGIN
    NEW.label_placement := ST_PointOnSurface(NEW.way);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;

BEGIN;
DROP TRIGGER IF EXISTS trigger_polygon ON planet_osm_polygon;
CREATE TRIGGER trigger_polygon BEFORE INSERT OR UPDATE ON planet_osm_polygon FOR EACH ROW EXECUTE PROCEDURE trigger_function_polygon();
COMMIT;

/* indexes */
CREATE INDEX planet_osm_point_power_index ON planet_osm_point USING gist(way) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');
CREATE INDEX planet_osm_polygon_power_index ON planet_osm_polygon USING gist(way) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');
CREATE INDEX planet_osm_polygon_label_index ON planet_osm_polygon USING gist(label_placement) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');

CREATE INDEX planet_osm_line_300000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 300000;
CREATE INDEX planet_osm_line_100000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 100000;
CREATE INDEX planet_osm_line_33000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 33000;
CREATE INDEX planet_osm_line_minor ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable', 'minor');

/* site relation handling */
CREATE OR REPLACE FUNCTION power_line_or_poly(geom geometry)
  RETURNS geometry AS
$$ BEGIN
  IF ST_IsClosed(geom) THEN
    RETURN ST_MakePolygon(geom);
  ELSE
    RETURN geom;
  END IF;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION power_multi_geom(osm_object text)
    RETURNS geometry AS $$
DECLARE
    osm_type text := substring(osm_object for 1);
    osm_id bigint := substring(osm_object from 2);
BEGIN
    CASE osm_type
        WHEN 'n' THEN
            RETURN ST_Transform(ST_SetSRID(ST_MakePoint(lon / 10000000.0, lat / 10000000.0), 4326), 3857) FROM planet_osm_nodes WHERE id=osm_id;
        WHEN 'r' THEN
            RETURN ST_Multi(ST_Collect(power_multi_geom(mem.object))) FROM (SELECT unnest(akeys(members::hstore)) AS object FROM planet_osm_rels WHERE id=osm_id) mem;
        WHEN 'w' THEN
            RETURN ST_Centroid(power_line_or_poly(ST_MakeLine(power_multi_geom('n'||mem.object)))) FROM (SELECT unnest(nodes) AS object FROM planet_osm_ways WHERE id=osm_id) mem;
    END CASE;
END; $$ LANGUAGE plpgsql;

DELETE FROM planet_osm_point WHERE osm_id<0;
INSERT INTO planet_osm_point
SELECT -id, 'plant', NULL, tags::hstore, ST_Centroid(power_multi_geom('r'||id)) FROM planet_osm_rels WHERE tags::hstore->'type'='site' AND tags::hstore->'power'='plant';

CREATE OR REPLACE FUNCTION trigger_site_relation_function()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        INSERT INTO planet_osm_point
        SELECT -id, 'plant', NULL, tags::hstore, ST_Centroid(power_multi_geom('r'||id)) FROM planet_osm_rels WHERE tags::hstore->'type'='site' AND tags::hstore->'power'='plant' AND id = NEW.id;
    ELSE
        DELETE FROM planet_osm_point WHERE -osm_id = OLD.id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql VOLATILE;

BEGIN;
DROP TRIGGER IF EXISTS trigger_site_relation ON planet_osm_rels;
CREATE TRIGGER trigger_site_relation AFTER INSERT OR UPDATE OR DELETE ON planet_osm_rels FOR EACH ROW EXECUTE PROCEDURE trigger_site_relation_function();
COMMIT;
