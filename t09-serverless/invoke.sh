#!/usr/bin/env bash

# Invoke the function manually and show the result.
#
# Usage: ./invoke.sh [YYYY-MM-DD]   (default: yesterday)

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

check_login
# output -raw prints one output of the OpenTofu configuration without quotes
function_name=$("$REPO_ROOT/tools/tofu.sh" "$REPO_ROOT/t09-serverless/infra" output -raw function_name)
payload='{}'
# With a date as argument, the payload is {"date": "..."}; \" is a quote inside
# double quotes
[[ -n "${1:-}" ]] && payload="{\"date\": \"$1\"}"
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
