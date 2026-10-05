#!/usr/bin/env bash
# Run the example queries, or open an interactive psql session with -i.
# Usage: ./query.sh [-i]
# Uses DATABASE_URL if it is set, otherwise the database from ./create-db.sh.
source "$(dirname "$0")/../lib/common.sh"

url="${DATABASE_URL:-}"
load_state t06
DATABASE_URL="${url:-${DATABASE_URL:-}}"
[[ -n "$DATABASE_URL" ]] || die "No database: set DATABASE_URL or run ./create-db.sh first."
cd "$(dirname "$0")"

if [[ "${1:-}" == "-i" ]]; then
  psql_run "$DATABASE_URL"
else
  psql_run "$DATABASE_URL" -f queries.sql
fi
