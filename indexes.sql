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

/* pretty print functions */
CREATE OR REPLACE FUNCTION volts_to_kv(volts text)
  RETURNS text AS
$$ BEGIN
  BEGIN
    RETURN format('%s kV', trim(to_char(volts::integer/1000.0, 'FM9990.9'), '.'));
  EXCEPTION WHEN OTHERS THEN
    RETURN volts;
  END;
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION format_capacity(watts bigint)
  RETURNS text AS
$$ BEGIN
  IF watts IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN format('%s MW', trim(to_char(watts/1000000.0, 'FM999990.99'), '.'));
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION format_voltage(volts text)
  RETURNS text AS
$$ BEGIN
  RETURN array_to_string((SELECT array_agg(volts_to_kv(e)) FROM unnest(string_to_array(volts, ';')) AS e), '; ');
END; $$ LANGUAGE plpgsql;

/* indexes */
CREATE INDEX planet_osm_point_power_index ON planet_osm_point USING gist(way) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');
CREATE INDEX planet_osm_polygon_power_index ON planet_osm_polygon USING gist(way) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');
CREATE INDEX planet_osm_polygon_label_index ON planet_osm_polygon USING gist(label_placement) WHERE power IN ('substation', 'sub_station', 'station', 'plant', 'generator');

CREATE INDEX planet_osm_line_300000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 300000;
CREATE INDEX planet_osm_line_100000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 100000;
CREATE INDEX planet_osm_line_33000v ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable') AND max_voltage >= 33000;
CREATE INDEX planet_osm_line_minor ON planet_osm_line USING gist(way) WHERE power IN ('line', 'cable', 'minor');
