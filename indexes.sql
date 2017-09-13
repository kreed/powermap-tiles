DO $$
BEGIN

CREATE INDEX planet_osm_point_min_zoom_6_index ON planet_osm_point USING gist(way) WHERE min_zoom <= 6;
CREATE INDEX planet_osm_point_min_zoom_8_index ON planet_osm_point USING gist(way) WHERE min_zoom <= 8;
CREATE INDEX planet_osm_point_min_zoom_10_index ON planet_osm_point USING gist(way) WHERE min_zoom <= 10;

CREATE INDEX planet_osm_line_min_zoom_1_index ON planet_osm_line USING gist(way) WHERE min_zoom <= 1;
CREATE INDEX planet_osm_line_min_zoom_3_index ON planet_osm_line USING gist(way) WHERE min_zoom <= 3;
CREATE INDEX planet_osm_line_min_zoom_6_index ON planet_osm_line USING gist(way) WHERE min_zoom <= 6;
CREATE INDEX planet_osm_line_min_zoom_8_index ON planet_osm_line USING gist(way) WHERE min_zoom <= 8;
CREATE INDEX planet_osm_line_min_zoom_10_index ON planet_osm_line USING gist(way) WHERE min_zoom <= 10;

CREATE INDEX planet_osm_polygon_min_zoom_6_index ON planet_osm_polygon USING gist(way) WHERE min_zoom <= 6;
CREATE INDEX planet_osm_polygon_min_zoom_8_index ON planet_osm_polygon USING gist(way) WHERE min_zoom <= 8;
CREATE INDEX planet_osm_polygon_min_zoom_10_index ON planet_osm_polygon USING gist(way) WHERE min_zoom <= 10;

END $$;

ANALYZE planet_osm_point;
ANALYZE planet_osm_line;
ANALYZE planet_osm_polygon;
