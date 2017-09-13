createdb:
	createdb -E UTF-8 -T template0 trex
	psql -d trex -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'

convertpbf:
	rm planet.o5m
	osmconvert planet-latest.osm.pbf --drop-author --out-o5m -o=planet.o5m

updateo5m:
	osmupdate planet.o5m planet-new.o5m --drop-author
	mv planet-new.o5m planet.o5m

filtero5m:
	osmfilter --parameter-file=osmfilter.params planet.o5m --out-o5m -o=planet-power.o5m

updatedb:
	osmconvert planet-power-imported.o5m planet-power.o5m --diff -o=planet-power.osc
	osm2pgsql -s -G -C 2048 -E 3857 -S osm2pgsql.style -j planet-power.osc -d trex -a --tag-transform-script osm2pgsql.lua
	mv planet-power.o5m planet-power-imported.o5m
	./grid.py trex
	rm -r cache
	./trex generate --config power.toml

import:
	osm2pgsql -s -G -C 2048 -E 3857 -S osm2pgsql.style -j planet-power-imported.o5m -d trex --tag-transform-script osm2pgsql.lua
	psql -d trex -f indexes.sql
	./grid.py trex
	rm -r cache
	./trex generate --config power.toml
