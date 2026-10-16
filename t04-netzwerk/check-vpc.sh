#!/usr/bin/env bash
# Check the test VMs created with --with-vm: the bastion in the public subnet
# reaches the internet, the private VM in the application subnet is reachable
# only through the bastion and reaches the internet only with --with-nat.
# Usage: ./check-vpc.sh
source "$(dirname "$0")/../lib/common.sh"

LAB=t04
require ssh nc
load_state "$LAB"
[[ -n "${BASTION_IP:-}" && -n "${PRIVATE_IP:-}" ]] \
  || die "No test VMs. Create the network with --with-vm first."
nat="${NAT:-false}"

# Own known_hosts file: the cloud reuses addresses, and ~/.ssh stays clean
opts=(-i "${SSH_PUBLIC_KEY%.pub}" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10
      -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$STATE_DIR/$LAB.known_hosts")
# shellcheck disable=SC2029  # the commands are meant to run on the VM
bastion() { ssh "${opts[@]}" "$SSH_USER@$BASTION_IP" "$@"; }
# ProxyCommand instead of -J, so that the options apply to both connections
# shellcheck disable=SC2029
private() {
  ssh "${opts[@]}" -o ProxyCommand="ssh ${opts[*]} -W %h:%p $SSH_USER@$BASTION_IP" \
    "$SSH_USER@$PRIVATE_IP" "$@"
}
# HTTP status of a well-known website, 000 if there is no connection
probe='curl --silent --output /dev/null --max-time 8 --write-out "%{http_code}" https://www.openstreetmap.org/ || true'
answers() { [[ "$1" =~ ^[23][0-9][0-9]$ ]] && echo yes || echo no; }

results=() failed=0
check() {   # check <description> <expected yes|no> <actual yes|no>
  local mark=ok
  [[ "$2" == "$3" ]] || { mark=UNEXPECTED; failed=1; }
  results+=("$(printf '%-11s %-44s expected: %-4s got: %s' "$mark" "$1" "$2" "$3")")
}
wait_for_ssh() {   # wait_for_ssh <bastion|private>; the VMs need a minute after creation
  local _
  for _ in $(seq 18); do
    "$1" true 2>/dev/null && return 0
    sleep 10
  done
  "$1" true
}

log "1/4 Bastion $BASTION_IP: SSH from here, internet through the gateway ..."
wait_for_ssh bastion \
  || die "No SSH connection to $BASTION_IP. Has your IP address changed? It is now $(my_ip)."
check "Bastion reaches the internet" yes "$(answers "$(bastion "$probe")")"

log "2/4 Private VM $PRIVATE_IP through the bastion ..."
if wait_for_ssh private; then reachable=yes; else reachable=no; fi
check "Private VM reachable through the bastion" yes "$reachable"

if [[ "$reachable" == yes ]]; then
  log "3/4 Private VM: name resolution and internet (only with --with-nat) ..."
  private "getent hosts www.openstreetmap.org" || warn "No DNS answer on the private VM"
  expected=no
  [[ "$nat" != true ]] || expected=yes
  check "Private VM reaches the internet" "$expected" "$(answers "$(private "$probe")")"
fi

log "4/4 Private VM directly from here (private address, no route to it) ..."
if nc -z -w 5 "$PRIVATE_IP" 22 2>/dev/null; then direct=yes; else direct=no; fi
check "Private VM reachable directly from here" no "$direct"

echo
printf '%s\n' "${results[@]}"
(( failed == 0 )) || die "Some results differ from the network design."
log "The network behaves as designed."
