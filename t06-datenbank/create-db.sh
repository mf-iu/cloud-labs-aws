#!/usr/bin/env bash
# Create an Amazon RDS for PostgreSQL 18 instance (db.t4g.micro) that only
# accepts connections from your IP address. Daily backups and point-in-time
# recovery are always on; the backups are kept for one day. Takes about
# 10 minutes.
# Usage: ./create-db.sh
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t06
check_login
load_state "$LAB"
[[ -z "${DB_ID:-}" ]] || die "Database $DB_ID exists already. Run ./destroy-db.sh first."

ip=$(my_ip)
vpc=$(default_vpc)
db_id=$(name "$LAB-db")
password=$(random_password)

log "Creating security group (PostgreSQL from $ip only) ..."
sg=$(aws ec2 create-security-group --group-name "$db_id" --vpc-id "$vpc" \
  --description "PostgreSQL, lab $LAB" \
  --tag-specifications "$(tag_spec security-group "$LAB" "$db_id")" \
  --query GroupId --output text)
save_state "$LAB" SECURITY_GROUP_ID "$sg"
aws ec2 authorize-security-group-ingress --group-id "$sg" --protocol tcp --port 5432 \
  --cidr "$ip/32" >/dev/null

# the current minor version of PostgreSQL 18, as in compose.yaml of PlaceFinder
version=$(aws rds describe-db-engine-versions --engine postgres --engine-version 18 \
  --default-only --query 'DBEngineVersions[0].EngineVersion' --output text)
log "Creating RDS instance $db_id (PostgreSQL $version, db.t4g.micro, 20 GB) ..."
# shellcheck disable=SC2046
aws rds create-db-instance \
  --db-instance-identifier "$db_id" \
  --engine postgres --engine-version "$version" \
  --db-instance-class db.t4g.micro \
  --allocated-storage 20 --storage-type gp3 \
  --db-name placefinder \
  --master-username pfadmin --master-user-password "$password" \
  --vpc-security-group-ids "$sg" \
  --publicly-accessible --no-multi-az \
  --backup-retention-period 1 \
  --tags $(aws_tags "$LAB") >/dev/null
save_state "$LAB" DB_ID "$db_id"

log "Waiting until the instance is available (about 10 minutes) ..."
aws rds wait db-instance-available --db-instance-identifier "$db_id"
host=$(aws rds describe-db-instances --db-instance-identifier "$db_id" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
save_state "$LAB" DATABASE_URL "postgresql://pfadmin:$password@$host:5432/placefinder?sslmode=require"

cat <<INFO

Database ready: $host
  Load data:   ./load-cities.sh
  Queries:     ./query.sh       (interactive: ./query.sh --interactive)
  PlaceFinder: ./test-api.sh    (smoke test of t05 with this database)
  Backups:     ./backups.sh
  Delete:      ./destroy-db.sh  (do not keep it running!)
The connection string is stored in .state/$LAB.env.
INFO
