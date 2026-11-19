#!/usr/bin/env bash

# Query places.parquet in the bucket of base with DuckDB on this computer:
# runs query_duckdb.py of cloud-labs-local with temporary keys of your AWS
# login. Arguments go on to query_duckdb.py, e.g. --explain.
#
# Usage: 08-analytics/query-duckdb.sh [--explain]

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

require uv
check_login
bucket=$(base_output bucket)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The CLI prints export lines with temporary keys of the login: access key,
# secret key and session token. eval runs them in this shell.
eval "$(aws configure export-credentials --format env)"
token=""
[[ -z "${AWS_SESSION_TOKEN:-}" ]] || token=", SESSION_TOKEN '$AWS_SESSION_TOKEN'"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# A DuckDB secret for this bucket only (SCOPE). query_duckdb.py runs the
# statement first; as an environment variable it shows up neither in the
# command line nor in "ps".
export DUCKDB_SECRET="CREATE SECRET lake (TYPE s3, KEY_ID '$AWS_ACCESS_KEY_ID',
    SECRET '$AWS_SECRET_ACCESS_KEY'$token, REGION '$AWS_REGION', SCOPE 's3://$bucket')"
uv run "$LOCAL_LABS/10-analytics/query_duckdb.py" "s3://$bucket/places/places.parquet" "$@"
