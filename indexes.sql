/* label handling */
ALTER TABLE planet_osm_polygon ADD COLUMN label_placement geometry(Geometry, 3857);
UPDATE planet_osm_polygon
  SET label_placement = ST_PointOnSurface(way);

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

ANALYZE planet_osm_point;
ANALYZE planet_osm_line;
ANALYZE planet_osm_polygon;
