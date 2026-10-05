#!/usr/bin/env bash
# Import points of interest from an OpenStreetMap extract with osm2pgsql.
# Usage: ./load-pois.sh [region]
#   region: path on download.geofabrik.de without "-latest.osm.pbf",
#   default: europe/germany/thueringen (about 150 MB)
# Tested with osm2pgsql 1.11 and 2.3. Uses DATABASE_URL like
# load-cities.sh.
source "$(dirname "$0")/../lib/common.sh"
require osm2pgsql

url="${DATABASE_URL:-}"
load_state t06
DATABASE_URL="${url:-${DATABASE_URL:-}}"
[[ -n "$DATABASE_URL" ]] || die "No database: set DATABASE_URL or run ./create-db.sh first."

region="${1:-europe/germany/thueringen}"
pbf="$DATA_DIR/$(basename "$region")-latest.osm.pbf"
if [[ ! -s "$pbf" ]]; then
  log "Downloading $region from Geofabrik ..."
  curl -fsSL -o "$pbf" "https://download.geofabrik.de/$region-latest.osm.pbf"
fi
cd "$(dirname "$0")"

log "Importing points of interest with osm2pgsql ..."
osm2pgsql --output=flex --style=pois.lua --database="$DATABASE_URL" "$pbf"

log "Creating geography column and index ..."
psql_run "$DATABASE_URL" -v ON_ERROR_STOP=1 -f pois.sql

log "Done: table pois. Data © OpenStreetMap contributors (ODbL)."
