#!/usr/bin/env bash

# Invoke the function by hand and show the end of its log and its result.
# With --async, Lambda queues the event like the schedule does and retries
# twice on failure; a failure after the retries lands in the dead-letter
# queue (extra task, -var dead_letter=true).
#
# Usage: 07-serverless/invoke.sh [--async] [YYYY-MM-DD]   (default: yesterday)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

mode=sync
if [[ "${1:-}" == "--async" ]]; then
    mode=async
    shift
fi

check_login
# output -raw prints one output of the OpenTofu configuration without quotes
function_name=$("$REPO_ROOT/tools/tofu.sh" "$REPO_ROOT/07-serverless/infra" output -raw function_name)
payload='{}'
# With a date as argument, the payload is {"date": "..."}; \" is a quote inside
# double quotes
[[ -n "${1:-}" ]] && payload="{\"date\": \"$1\"}"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ "$mode" == async ]]; then
    # InvocationType Event: Lambda answers 202 at once and runs the function
    # later, as for the schedule
    aws lambda invoke --function-name "$function_name" --invocation-type Event \
        --cli-binary-format raw-in-base64-out --payload "$payload" /dev/null >/dev/null
    log "Queued. On failure Lambda retries after about 1 and 2 minutes; then the event goes to the dead-letter queue."
    exit 0
fi

# A temporary file for the answer; trap deletes it when the script ends
out=$(mktemp)
trap 'rm --force "$out"' EXIT
# --log-type Tail returns the end of the log, base64-encoded in LogResult;
# base64 --decode makes it readable. The answer of the function goes into the
# file $out.
aws lambda invoke --function-name "$function_name" --cli-binary-format raw-in-base64-out \
    --payload "$payload" --log-type Tail --query LogResult --output text "$out" | base64 --decode | tail --lines 20
echo
cat "$out"
echo
