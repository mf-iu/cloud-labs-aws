#!/usr/bin/env bash
# Network diagnosis for a host name: DNS, TCP/TLS handshake, certificate.
# Usage: ./diagnose.sh [host]   (default: www.openstreetmap.org)
set -euo pipefail
host="${1:-www.openstreetmap.org}"

section() { printf '\n\033[1;36m=== %s ===\033[0m\n' "$*"; }

section "DNS: A and AAAA records"
dig +short "$host" A
dig +short "$host" AAAA

section "DNS: delegation from the root (dig +trace, shortened)"
dig +trace +nodnssec "$host" | grep -E 'IN\s+(NS|A|CNAME)\s' | tail -n 12

section "HTTP over TLS: connection, handshake and headers (curl -v)"
curl -sS -v -o /dev/null "https://$host/" 2>&1 | grep -E '^\*|^< ' | head -n 40

section "TLS certificate chain (openssl s_client)"
openssl s_client -connect "$host:443" -servername "$host" -showcerts </dev/null 2>/dev/null \
  | grep -E 'Protocol|Cipher|^ *[0-9] s:|^ *i:' | head -n 12
