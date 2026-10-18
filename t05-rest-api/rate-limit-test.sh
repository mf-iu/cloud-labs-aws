#!/usr/bin/env bash
# Send many requests at once and count the answers: 200 while the rate limit
# of the API gateway allows them, then 429 Too Many Requests.
#
# Usage: ./rate-limit-test.sh [--requests <n>] [--parallel <n>] [--header 'Name: value'] [base url]
#   base url    default: the gateway from create-api-gateway.sh, with its key
#   --requests  number of requests, default: 60
#   --parallel  requests at the same time, default: 10
#   --header    send this header with every request, e.g. an API key
source "$(dirname "$0")/../lib/common.sh"

USAGE="Usage: ./rate-limit-test.sh [--requests <n>] [--parallel <n>] [--header 'Name: value'] [base url]"
requests=60
parallel=10
headers=()
base=""
while (( $# )); do
  case "$1" in
    --requests|--parallel)
      [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "$1 needs a positive number. $USAGE"
      if [[ "$1" == --requests ]]; then requests=$2; else parallel=$2; fi
      shift ;;
    --header) (( $# > 1 )) || die "$USAGE"; headers+=(--header "$2"); shift ;;
    -*) die "Unknown option $1. $USAGE" ;;
    *) base=$1 ;;
  esac
  shift
done
require curl
if [[ -z "$base" ]]; then
  load_state t05
  [[ -n "${API_URL:-}" ]] || die "No API gateway. Run ./create-api-gateway.sh first or pass a URL."
  base=$API_URL
  [[ -z "${API_HEADER:-}" ]] || headers+=(--header "$API_HEADER")
fi
url="${base%/}/health"

statuses=$(mktemp)
trap 'rm --force "$statuses"' EXIT
log "Sending $requests requests to $url, $parallel at a time ..."
start=$SECONDS
for (( i = 1; i <= requests; i++ )); do
  curl --silent --output /dev/null --max-time 30 --write-out '%{http_code}\n' \
    "${headers[@]}" "$url" >>"$statuses" &
  (( i % parallel )) || wait
done
wait
log "Done after $(( SECONDS - start ))s. Answers by status code:"
sort "$statuses" | uniq --count | awk '{ printf "  %s  %4d times\n", $2, $1 }'

echo
echo "One more request, with the response headers:"
curl --silent --show-error --include --max-time 30 "${headers[@]}" "$url" | tr --delete '\r'
echo
grep --quiet '^429$' "$statuses" \
  || die "No 429: the limit was not reached. Try more requests: ./rate-limit-test.sh --requests 200"
log "The gateway limited the requests (429). Wait a minute before the next smoke test."
