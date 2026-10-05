#!/usr/bin/env bash
# Delete the VM, its security group and the imported key pair.
# Usage: ./destroy-vm.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t02
check_login
load_state "$LAB"
[[ -n "${INSTANCE_ID:-}${SECURITY_GROUP_ID:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete VM ${INSTANCE_ID:-?} and its security group?" || exit 0

if [[ -n "${INSTANCE_ID:-}" ]]; then
  log "Terminating $INSTANCE_ID ..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
  aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
fi
if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
  aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID"
fi
# The key pair is shared with t04; delete it only if no state needs it
if [[ ! -f "$(state_file t04)" ]]; then
  aws ec2 delete-key-pair --key-name "$(name key)" >/dev/null || true
fi
clear_state "$LAB"
log "VM deleted."
