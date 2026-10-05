#!/usr/bin/env bash
# Delete the RDS instance without final snapshot, and its security group.
# Usage: ./destroy-db.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t06
check_login
load_state "$LAB"
[[ -n "${DB_ID:-}${SECURITY_GROUP_ID:-}" ]] || { log "Nothing to delete."; exit 0; }
confirm "Delete database ${DB_ID:-?} including all data and backups?" || exit 0

if [[ -n "${DB_ID:-}" ]]; then
  log "Deleting $DB_ID (takes a few minutes) ..."
  aws rds delete-db-instance --db-instance-identifier "$DB_ID" \
    --skip-final-snapshot --delete-automated-backups >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$DB_ID"
fi
if [[ -n "${SECURITY_GROUP_ID:-}" ]]; then
  aws ec2 delete-security-group --group-id "$SECURITY_GROUP_ID"
fi
clear_state "$LAB"
log "Database deleted."
