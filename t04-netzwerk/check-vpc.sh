#!/usr/bin/env bash
# Compare the network with the design of session 4 (part 1): address ranges
# and routes of the six subnets, incoming rules of the security groups.
# With the test VMs of --with-vm, also check what is reachable from where
# (part 2): the bastion in the public subnet reaches the internet, the
# private VM only through the bastion and the internet only with --with-nat.
# Usage: ./check-vpc.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t04
check_login
load_state "$LAB"
[[ -n "${VPC_ID:-}" ]] || die "No network. Create it with ./create-vpc.sh first."
nat="${NAT:-false}"
ec2() { aws ec2 "$@"; }

results=() failed=0
check() {   # check <description> <expected> <actual>
  local mark=ok
  [[ "$2" == "$3" ]] || { mark=UNEXPECTED; failed=1; }
  results+=("$(printf '%-10s %-40s expected: %-22s got: %s' "$mark" "$1" "$2" "${3:-(nothing)}")")
}
joined() { local lines; lines=$(sort); echo "${lines//$'\n'/, }"; }   # stdin lines -> "a, b"

# ---------------------------------------------------------------- part 1: design
log "Design 1/2: subnets and their route to the internet (0.0.0.0/0) ..."
internet_route() {   # internet_route <subnet id>: internet gateway, NAT gateway or none
  local target
  target=$(ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$1" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].[GatewayId,NatGatewayId]" \
    --output text)
  case "$target" in
    igw-*) echo "internet gateway" ;;
    *nat-*) echo "NAT gateway" ;;
    *) echo none ;;
  esac
}
app_route=none
[[ "$nat" != true ]] || app_route="NAT gateway"
names=(public-a public-b app-a app-b db-a db-b)
ranges=(10.20.0.0/24 10.20.1.0/24 10.20.10.0/24 10.20.11.0/24 10.20.20.0/24 10.20.21.0/24)
routes=("internet gateway" "internet gateway" "$app_route" "$app_route" none none)
read -ra ids <<<"$SUBNET_IDS"
for i in "${!names[@]}"; do
  range=$(ec2 describe-subnets --subnet-ids "${ids[$i]}" --query 'Subnets[0].CidrBlock' --output text)
  check "Subnet ${names[$i]}: address range" "${ranges[$i]}" "$range"
  check "Subnet ${names[$i]}: route to the internet" "${routes[$i]}" "$(internet_route "${ids[$i]}")"
done

log "Design 2/2: incoming rules of the security groups ..."
read -r sg_lb sg_app sg_db <<<"$SECURITY_GROUP_IDS"
declare -A sg_name=([$sg_lb]=sg-lb [$sg_app]=sg-app [$sg_db]=sg-db)
rules() {   # rules <group id>: incoming rules as "port from source"
  ec2 describe-security-group-rules --filters "Name=group-id,Values=$1" \
    --query 'SecurityGroupRules[?!IsEgress].[FromPort,CidrIpv4,ReferencedGroupInfo.GroupId]' \
    --output text |
    while read -r port cidr group; do
      if [[ "$cidr" != None ]]; then echo "$port from $cidr"; else echo "$port from ${sg_name[$group]:-$group}"; fi
    done | joined
}
check "sg-lb: incoming" "443 from 0.0.0.0/0" "$(rules "$sg_lb")"
check "sg-app: incoming" "8000 from sg-lb" "$(rules "$sg_app")"
check "sg-db: incoming" "5432 from sg-app" "$(rules "$sg_db")"

log "Usable addresses per subnet (AWS reserves five per subnet):"
# shellcheck disable=SC2016  # backticks are JMESPath literals
ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone,AvailableIpAddressCount]' \
  --output table

# ---------------------------------------------------------------- part 2: reachability
if [[ -z "${BASTION_IP:-}" || -z "${PRIVATE_IP:-}" ]]; then
  log "No test VMs: reachability not checked (optional: create the network with --with-vm)."
else
  require ssh nc
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
  wait_for_ssh() {   # wait_for_ssh <bastion|private>; the VMs need a minute after creation
    local _
    for _ in $(seq 18); do
      "$1" true 2>/dev/null && return 0
      sleep 10
    done
    "$1" true
  }

  log "Reachability 1/4: bastion $BASTION_IP, SSH from here, internet through the gateway ..."
  wait_for_ssh bastion \
    || die "No SSH connection to $BASTION_IP. Has your IP address changed? It is now $(my_ip)."
  check "Bastion reaches the internet" yes "$(answers "$(bastion "$probe")")"

  log "Reachability 2/4: private VM $PRIVATE_IP through the bastion ..."
  if wait_for_ssh private; then reachable=yes; else reachable=no; fi
  check "Private VM reachable through bastion" yes "$reachable"

  if [[ "$reachable" == yes ]]; then
    log "Reachability 3/4: private VM, name resolution and internet (only with --with-nat) ..."
    private "getent hosts www.openstreetmap.org" || warn "No DNS answer on the private VM"
    expected=no
    [[ "$nat" != true ]] || expected=yes
    check "Private VM reaches the internet" "$expected" "$(answers "$(private "$probe")")"
  fi

  log "Reachability 4/4: private VM directly from here (private address, no route to it) ..."
  if nc -z -w 5 "$PRIVATE_IP" 22 2>/dev/null; then direct=yes; else direct=no; fi
  check "Private VM reachable directly from here" no "$direct"
fi

echo
printf '%s\n' "${results[@]}"
(( failed == 0 )) || die "Some results differ from the network design."
log "The network matches the design."
