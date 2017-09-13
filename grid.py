#!/usr/bin/env python3
import psycopg2
import sys
from pprint import pprint

conn = psycopg2.connect("dbname='" + sys.argv[1] + "'")
cur = conn.cursor()

# osm2pgsql doesn't have any support for site relations, so we process those here.
# It would be nice to eventually do this in osm2pgsql (maybe through the lua script
# possible).
# To process we create a geometry collection from the all the children of the site
# relation and store the center of that geometry.
cur.execute("""
CREATE OR REPLACE FUNCTION pg_temp.line_or_poly(geom geometry)
  RETURNS geometry AS
$$ BEGIN
  IF ST_IsClosed(geom) THEN
    RETURN ST_MakePolygon(geom);
  ELSE
    RETURN geom;
  END IF;
END; $$ LANGUAGE plpgsql;

CREATE FUNCTION pg_temp.multi_geom(osm_object text)
RETURNS geometry AS $$
DECLARE
    osm_type text := substring(osm_object for 1);
    osm_id bigint := substring(osm_object from 2);
BEGIN
    CASE osm_type
        WHEN 'n' THEN
            RETURN ST_Transform(ST_SetSRID(ST_MakePoint(lon / 10000000.0, lat / 10000000.0), 4326), 3857) FROM planet_osm_nodes WHERE id=osm_id;
        WHEN 'r' THEN
            RETURN ST_Multi(ST_Collect(pg_temp.multi_geom(mem.object))) FROM (SELECT unnest(akeys(members::hstore)) AS object FROM planet_osm_rels WHERE id=osm_id) mem;
        WHEN 'w' THEN
            RETURN ST_Centroid(pg_temp.line_or_poly(ST_MakeLine(pg_temp.multi_geom('n'||mem.object)))) FROM (SELECT unnest(nodes) AS object FROM planet_osm_ways WHERE id=osm_id) mem;
    END CASE;
END; $$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS plant_site_relations (osm_id bigint, way geometry, tags hstore);
CREATE INDEX IF NOT EXISTS plant_site_relations_idx ON plant_site_relations USING gist(way);
TRUNCATE plant_site_relations;
INSERT INTO plant_site_relations
SELECT id, ST_Centroid(pg_temp.multi_geom('r'||id)), tags::hstore FROM planet_osm_rels WHERE tags::hstore->'type'='site' AND tags::hstore->'power'='plant';
""")

# Power grid locating script.
# This will start at a specified power line and iterates through all the connected lines.
# Based off of the keepright floating islands check.

seed_way = 39835701 # STP line

# Find all powerlines. Exclude lines manually specified to be on a different grid
# (with transmission_system=*), those noted to be synchronous ties, and those that contain
# nodes that look like asynchronous ties or open switches.
cur.execute("""
	CREATE TEMP TABLE _tmp_powerlines AS
	WITH grid_edges AS (
		SELECT osm_id FROM planet_osm_point p
		WHERE ((p.tags->'power'='converter' AND p.tags->'converter'='back-to-back')
			OR (p.tags->'power'='transformer' AND p.tags->'transformer'='variable_frequency')
			OR (p.tags->'power'='switch' AND p.tags->'note'~*'normally open')
		)
	)
	SELECT osm_id AS id, l.tags, nodes
	FROM planet_osm_line l INNER JOIN planet_osm_ways w ON l.osm_id = w.id
	WHERE (l.tags->'power'='line' OR l.tags->'power'='busbar' OR l.tags->'power'='cable')
	AND (NOT l.tags ? 'note' OR l.tags->'note'!~*'synchronous')
	AND (NOT l.tags ? 'transmission_system' OR l.tags->'transmission_system'~*'ERCOT')
	AND NOT EXISTS (SELECT NULL FROM unnest(nodes) nid INNER JOIN grid_edges ON nid=grid_edges.osm_id)
""")
print('{:,d} lines'.format(cur.rowcount))

# Find nodes shared between our powerlines
cur.execute("""
	CREATE TEMP TABLE _tmp_junctions AS
	WITH _tmp_nodes AS (
		SELECT id AS way_id, unnest(nodes) AS node_id
		FROM _tmp_powerlines
	)
	SELECT * FROM (
		SELECT node_id FROM _tmp_nodes
		GROUP BY (node_id)
		HAVING count(DISTINCT way_id)>1
	) junction_nodes INNER JOIN _tmp_nodes USING (node_id)
""")
print('{:,d} junctions'.format(cur.rowcount))

# contains all the connected ways found
cur.execute('CREATE TEMP TABLE _tmp_grid_ways (way_id bigint NOT NULL, PRIMARY KEY (way_id))')
# contains connected ways found in the current round
cur.execute('CREATE TEMP TABLE _tmp_iter_ways (way_id bigint NOT NULL, PRIMARY KEY (way_id))')
# contains nodes for connected ways found in the current round
cur.execute('CREATE TEMP TABLE _tmp_iter_nodes (node_id bigint NOT NULL)')

cur.execute("INSERT INTO _tmp_grid_ways (way_id) VALUES (%s)", (seed_way,))
cur.execute("INSERT INTO _tmp_iter_ways (way_id) VALUES (%s)", (seed_way,))
count = 1

while count:
	# first find nodes that belong to ways found in the last round
	# it is sufficient to only consider ways found during the round before here!
	cur.execute("TRUNCATE TABLE _tmp_iter_nodes")
	cur.execute("""
		INSERT INTO _tmp_iter_nodes (node_id)
		SELECT DISTINCT wn.node_id
		FROM _tmp_iter_ways w INNER JOIN _tmp_junctions wn USING (way_id)
	""")

	# remove ways of last round
	cur.execute("TRUNCATE TABLE _tmp_iter_ways")

	# insert ways that are connected to nodes found before. these make the starting
	# set for the next round
	cur.execute("""
		INSERT INTO _tmp_iter_ways (way_id)
		SELECT DISTINCT wn.way_id
		FROM (_tmp_junctions wn INNER JOIN _tmp_iter_nodes n USING (node_id)) LEFT JOIN _tmp_grid_ways w ON wn.way_id=w.way_id
		WHERE w.way_id IS NULL
	""")
	count = cur.rowcount

	# finally add newly found ways in collector table containing all ways
	cur.execute("INSERT INTO _tmp_grid_ways SELECT way_id FROM _tmp_iter_ways")
	print('{:,d} connected lines found'.format(count))

cur.execute("""UPDATE planet_osm_line
	SET grid = (CASE WHEN EXISTS ( SELECT NULL FROM _tmp_grid_ways WHERE way_id = osm_id ) THEN 'ercot' ELSE NULL END)
""")

cur.close()

conn.commit()
