#!/usr/bin/env bash

# Delete the VM, its security group and the imported key pair.
#
# Usage: ./destroy-vm.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

source "$(dirname "$0")/../lib/provider.sh"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

LAB=t02
check_login
# Read the ids that create-vm.sh saved in .state/t02.env
load_state "$LAB"
# Both ids joined are empty only if neither exists; { ...; } groups the two
# commands
[[ -n "${INSTANCE_ID:-}${SECURITY_GROUP_ID:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete VM ${INSTANCE_ID:-?} and its security group?" || exit 0

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [[ -n "${INSTANCE_ID:-}" ]]; then
    log "Terminating $INSTANCE_ID ..."
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
    # wait polls until the instance is terminated; only then can its security
    # group be deleted
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
fi
if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
    aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID"
fi

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The key pair is shared with t04; delete it only if no state needs it
if [[ ! -f "$(state_file t04)" ]]; then
    # || true: no error if the key pair is gone already
    aws ec2 delete-key-pair --key-name "$(name key)" >/dev/null || true
fi
clear_state "$LAB"
log "VM deleted."
