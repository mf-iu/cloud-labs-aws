#!/usr/bin/env bash
# Run an SQL query with Amazon Athena on the GeoParquet file in S3.
# Usage: ./athena.sh ["SQL"]   (default: largest places per country)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

check_login
tofu_out() { "$REPO_ROOT/tools/tofu.sh" "$REPO_ROOT/t10-datenanalyse/infra" output -raw "$1"; }
workgroup=$(tofu_out athena_workgroup)
database=$(tofu_out glue_database)

sql="${1:-SELECT country_code, count(*) AS places, max_by(name, population) AS largest
FROM places GROUP BY country_code ORDER BY places DESC LIMIT 10}"

log "Running in workgroup $workgroup:"
echo "$sql"
id=$(aws athena start-query-execution --work-group "$workgroup" \
  --query-execution-context "Database=$database" \
  --query-string "$sql" --query QueryExecutionId --output text)

while true; do
  state=$(aws athena get-query-execution --query-execution-id "$id" \
    --query QueryExecution.Status.State --output text)
  [[ "$state" == "QUEUED" || "$state" == "RUNNING" ]] || break
  sleep 2
done
if [[ "$state" != "SUCCEEDED" ]]; then
  aws athena get-query-execution --query-execution-id "$id" \
    --query QueryExecution.Status.StateChangeReason --output text
  die "Query $state"
fi

aws athena get-query-results --query-execution-id "$id" --output json | python3 -c '
import json, sys
rows = [[c.get("VarCharValue", "") for c in r["Data"]] for r in json.load(sys.stdin)["ResultSet"]["Rows"]]
widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))] if rows else []
for row in rows:
    print("  ".join(v.ljust(w) for v, w in zip(row, widths)))
'
scanned=$(aws athena get-query-execution --query-execution-id "$id" \
  --query QueryExecution.Statistics.DataScannedInBytes --output text)
log "Data scanned: $scanned bytes (Athena charges 5 USD per TB, minimum 10 MB per query)"
