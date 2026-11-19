#!/usr/bin/env bash

# Convert GeoNames cities15000 into GeoParquet with the script of
# cloud-labs-local and upload the file into the bucket of base, under places/.
#
# Usage: 08-analytics/upload.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require uv
check_login
bucket=$(base_output bucket)
# The file lies next to the other downloads in cloud-labs-local/.state/data
parquet="$DATA_DIR/places.parquet"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# download_cities (lib/common.sh) prints the path of cities15000.txt and
# downloads it first if needed
uv run "$LOCAL_LABS/10-analytics/export_geoparquet.py" "$(download_cities)" "$parquet"
aws s3 cp "$parquet" "s3://$bucket/places/places.parquet"
log "Uploaded to s3://$bucket/places/places.parquet. Next: 08-analytics/query-duckdb.sh"
