db ?= power

createdb:
	createdb -E UTF-8 -T template0 $(db)
	psql -d $(db) -c 'CREATE EXTENSION postgis; CREATE EXTENSION hstore;'

convertpbf:
	rm -f planet.o5m
	osmconvert planet-latest.osm.pbf --drop-author --out-o5m -o=planet.o5m

convertxml:
	rm -f planet.o5m
	lbzcat planet-*.osm.bz2 | osmconvert - --drop-author --out-o5m -o=planet.o5m

updateo5m:
	osmupdate planet.o5m planet-new.o5m --drop-author
	mv planet-new.o5m planet.o5m

filtero5m:
	osmfilter --parameter-file=osmfilter.params planet.o5m --out-o5m -o=planet-power.o5m

updatedb:
	osmconvert planet-power-imported.o5m planet-power.o5m --diff -o=planet-power.osc
	osm2pgsql -s -G -C 2048 -E 3857 -S osm2pgsql.style -j planet-power.osc -d $(db) -a --tag-transform-script osm2pgsql.lua
	mv planet-power.o5m planet-power-imported.o5m
	./grid.py $(db)
	rm -rf cache
	./trex generate --config power.toml --minzoom 0 --maxzoom 6

import:
	osm2pgsql -s -G -C 2048 -E 3857 -S osm2pgsql.style -j planet-power-imported.o5m -d $(db) --tag-transform-script osm2pgsql.lua
	psql -d $(db) -f indexes.sql
	./grid.py $(db)
	rm -rf cache
	./trex generate --config power.toml --minzoom 0 --maxzoom 6
