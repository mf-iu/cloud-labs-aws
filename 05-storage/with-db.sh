#!/usr/bin/env bash
# Run a script of cloud-labs-local/06-postgis with the managed database from
# create-db.sh: it sets DATABASE_URL, the scripts there use it instead of the
# local database.
# Usage: ./with-db.sh <script> [arguments]
# Examples: ./with-db.sh load-cities.sh
#           ./with-db.sh query.sh --interactive
#           ./with-db.sh test-api.sh
source "$(dirname "$0")/../lib/provider.sh"

[[ $# -ge 1 ]] || die "Usage: ./with-db.sh <script> [arguments], e.g. ./with-db.sh load-cities.sh"
script="$LOCAL_LABS/06-postgis/$1"
shift
[[ -x "$script" ]] || die "No script $script. Scripts: $(cd "$LOCAL_LABS/06-postgis" && echo ./*.sh)"
load_state t06
[[ -n "${DATABASE_URL:-}" ]] || die "No database. Run ./create-db.sh first."
export DATABASE_URL
exec "$script" "$@"
