#!/usr/bin/env bash
# Delete everything created by create-vpc.sh, in reverse order.
# Usage: ./destroy-vpc.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t04
check_login
load_state "$LAB"
[[ -n "${VPC_ID:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete VPC $VPC_ID with all subnets, gateways and test VMs?" || exit 0
ec2() { aws ec2 "$@"; }

if [[ -n "${INSTANCE_IDS:-}" ]]; then
  log "Terminating test VMs ..."
  # shellcheck disable=SC2086  # several ids on purpose
  ec2 terminate-instances --instance-ids $INSTANCE_IDS >/dev/null
  # shellcheck disable=SC2086
  ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
fi
if [[ -n "${NAT_GATEWAY_ID:-}" ]]; then
  log "Deleting NAT gateway ..."
  ec2 delete-nat-gateway --nat-gateway-id "$NAT_GATEWAY_ID" >/dev/null
  ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_GATEWAY_ID"
fi
if [[ -n "${EIP_ALLOCATION_ID:-}" ]]; then
  ec2 release-address --allocation-id "$EIP_ALLOCATION_ID"
fi
# Remove the cross references between the groups before deleting them
for sg in ${SECURITY_GROUP_IDS:-} ${SSH_SECURITY_GROUP_IDS:-}; do
  rules=$(ec2 describe-security-group-rules --filters "Name=group-id,Values=$sg" \
    --query 'SecurityGroupRules[?!IsEgress].SecurityGroupRuleId' --output text)
  if [[ -n "$rules" ]]; then
    # shellcheck disable=SC2086
    ec2 revoke-security-group-ingress --group-id "$sg" --security-group-rule-ids $rules >/dev/null
  fi
done
for sg in ${SECURITY_GROUP_IDS:-} ${SSH_SECURITY_GROUP_IDS:-}; do
  ec2 delete-security-group --group-id "$sg"
done
for table in ${ROUTE_TABLE_IDS:-}; do
  for assoc in $(ec2 describe-route-tables --route-table-ids "$table" \
      --query 'RouteTables[0].Associations[].RouteTableAssociationId' --output text); do
    ec2 disassociate-route-table --association-id "$assoc"
  done
  ec2 delete-route-table --route-table-id "$table"
done
for subnet in ${SUBNET_IDS:-}; do
  ec2 delete-subnet --subnet-id "$subnet"
done
if [[ -n "${IGW_ID:-}" ]]; then
  ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
  ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
fi
ec2 delete-vpc --vpc-id "$VPC_ID"
if [[ ! -f "$(state_file t02)" ]]; then
  ec2 delete-key-pair --key-name "$(name key)" >/dev/null || true
fi
clear_state "$LAB"
rm --force "$STATE_DIR/$LAB.known_hosts"   # host keys of the test VMs (check-vpc.sh)
log "Network deleted."
