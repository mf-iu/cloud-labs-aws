#!/usr/bin/env bash
# Convert cities15000 into GeoParquet and upload it into the data lake.
# Usage: ./upload.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

require uv
check_login
cd "$(dirname "$0")"
bucket=$("$REPO_ROOT/tools/tofu.sh" infra output -raw bucket)
parquet="$DATA_DIR/places.parquet"

uv run export_geoparquet.py "$(download_cities)" "$parquet"
aws s3 cp "$parquet" "s3://$bucket/places/places.parquet"
log "Uploaded. Next: ./query-duckdb.sh and ./athena.sh"
