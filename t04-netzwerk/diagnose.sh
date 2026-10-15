#!/usr/bin/env bash
# Network diagnosis for a host name: DNS, TCP/TLS handshake, certificate.
# Usage: ./diagnose.sh [host]   (default: www.openstreetmap.org)
set -o errexit -o nounset -o pipefail
host="${1:-www.openstreetmap.org}"

section() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

section "DNS: A and AAAA records"
dig +short "$host" A
dig +short "$host" AAAA

section "DNS: delegation from the root (dig +trace, shortened)"
dig +trace +nodnssec "$host" | grep --extended-regexp 'IN\s+(NS|A|CNAME)\s' | tail --lines 12

section "HTTP over TLS: connection, handshake and headers (curl --verbose)"
curl --silent --show-error --verbose --output /dev/null "https://$host/" 2>&1 | grep --extended-regexp '^\*|^< ' | head --lines 40

section "TLS certificate chain (openssl s_client)"
openssl s_client -connect "$host:443" -servername "$host" -showcerts </dev/null 2>/dev/null \
  | grep --extended-regexp 'Protocol|Cipher|^ *[0-9] s:|^ *i:' | head --lines 12
