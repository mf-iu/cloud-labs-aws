#!/usr/bin/env bash
# Show the automated backups of the RDS instance: retention, backup window,
# snapshots and the time span of a point-in-time restore. Changes nothing.
# Usage: ./backups.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t06
check_login
load_state "$LAB"
[[ -n "${DB_ID:-}" ]] || die "No database. Run ./create-db.sh first."

# minutes between an ISO 8601 time and now
minutes_ago() {   # minutes_ago <time>
  python3 -c 'import datetime as d, sys
print(round((d.datetime.now(d.timezone.utc) - d.datetime.fromisoformat(sys.argv[1])).total_seconds() / 60))' "$1"
}

log "Backup settings of $DB_ID:"
aws rds describe-db-instances --db-instance-identifier "$DB_ID" \
  --query 'DBInstances[0].{RetentionDays: BackupRetentionPeriod, BackupWindowUTC: PreferredBackupWindow, LatestRestorableTime: LatestRestorableTime}' \
  --output table

log "Automated snapshots (the first right after creation, then one a day):"
aws rds describe-db-snapshots --db-instance-identifier "$DB_ID" --snapshot-type automated \
  --query 'DBSnapshots[].[DBSnapshotIdentifier, SnapshotCreateTime, Status]' --output table

# snapshots plus the WAL archive (every five minutes) give the restore window
window=$(aws rds describe-db-instance-automated-backups --db-instance-identifier "$DB_ID" \
  --query 'DBInstanceAutomatedBackups[0].RestoreWindow.[EarliestTime, LatestTime]' --output text)
read -r earliest latest <<<"$window"
if [[ -z "$latest" || "$latest" == "None" ]]; then
  warn "No restore window yet: the first backup runs after creation. Try again in a few minutes."
  exit 0
fi
cat <<INFO

Point-in-time restore possible from $earliest
                                 to $latest ($(minutes_ago "$latest") minutes ago)
Data written after the latest restorable time would be lost (RPO: about five minutes).
A restore creates a new instance with a new endpoint (RTO: about 10 minutes plus the
switch of the application). Not done here, it would cost a second instance:
  aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier $DB_ID \\
    --target-db-instance-identifier $DB_ID-restored --use-latest-restorable-time
INFO
