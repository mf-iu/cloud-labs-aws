#!/usr/bin/env bash
# Run query_duckdb.py with temporary credentials of your AWS login.
# Usage: ./query-duckdb.sh [overture release]
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

require uv
check_login
cd "$(dirname "$0")"
bucket=$("$REPO_ROOT/tools/tofu.sh" infra output -raw bucket)
# DuckDB reads AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY and AWS_SESSION_TOKEN
eval "$(aws configure export-credentials --format env)"
uv run query_duckdb.py "$bucket" "${1:-${OVERTURE_RELEASE:-}}"
