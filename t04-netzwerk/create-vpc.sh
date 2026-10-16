#!/usr/bin/env bash
# Create the PlaceFinder network design from session 4:
# VPC 10.20.0.0/16 with public, application and database subnets in two
# availability zones, routing tables and security groups.
#
# Usage: ./create-vpc.sh [--with-vm] [--with-nat]
#   --with-vm   two test VMs: a bastion in the public subnet (SSH from your IP
#               only) and a VM without public address in the application
#               subnet (SSH only from the bastion); check with ./check-vpc.sh
#   --with-nat  NAT gateway for the application subnets (about 1 USD per day!)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t04
with_vm=false
with_nat=false
for arg in "$@"; do
  case "$arg" in
    --with-vm) with_vm=true ;;
    --with-nat) with_nat=true ;;
    *) die "Unknown option: $arg" ;;
  esac
done
check_login
load_state "$LAB"
[[ -z "${VPC_ID:-}" ]] || die "VPC $VPC_ID exists already. Run ./destroy-vpc.sh first."

ec2() { aws ec2 "$@"; }
mapfile -t zones < <(ec2 describe-availability-zones --filters Name=state,Values=available \
  --query 'AvailabilityZones[0:2].ZoneName' --output text | tr '\t' '\n')

log "Creating VPC 10.20.0.0/16 ..."
vpc=$(ec2 create-vpc --cidr-block 10.20.0.0/16 \
  --tag-specifications "$(tag_spec vpc "$LAB" "$(name vpc)")" --query Vpc.VpcId --output text)
save_state "$LAB" VPC_ID "$vpc"
ec2 modify-vpc-attribute --vpc-id "$vpc" --enable-dns-hostnames

igw=$(ec2 create-internet-gateway \
  --tag-specifications "$(tag_spec internet-gateway "$LAB" "$(name igw)")" \
  --query InternetGateway.InternetGatewayId --output text)
save_state "$LAB" IGW_ID "$igw"
ec2 attach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$vpc"

subnet() {   # subnet <cidr> <zone> <name>; prints the subnet id
  ec2 create-subnet --vpc-id "$vpc" --cidr-block "$1" --availability-zone "$2" \
    --tag-specifications "$(tag_spec subnet "$LAB" "$(name "$3")")" \
    --query Subnet.SubnetId --output text
}
log "Creating subnets in ${zones[*]} ..."
public_a=$(subnet 10.20.0.0/24 "${zones[0]}" public-a)
public_b=$(subnet 10.20.1.0/24 "${zones[1]}" public-b)
app_a=$(subnet 10.20.10.0/24 "${zones[0]}" app-a)
app_b=$(subnet 10.20.11.0/24 "${zones[1]}" app-b)
db_a=$(subnet 10.20.20.0/24 "${zones[0]}" db-a)
db_b=$(subnet 10.20.21.0/24 "${zones[1]}" db-b)
save_state "$LAB" SUBNET_IDS "$public_a $public_b $app_a $app_b $db_a $db_b"

route_table() {   # route_table <name> <subnet ids...>; prints the table id
  local table
  table=$(ec2 create-route-table --vpc-id "$vpc" \
    --tag-specifications "$(tag_spec route-table "$LAB" "$(name "$1")")" \
    --query RouteTable.RouteTableId --output text)
  shift
  for id in "$@"; do ec2 associate-route-table --route-table-id "$table" --subnet-id "$id" >/dev/null; done
  echo "$table"
}
log "Creating routing tables: public -> internet gateway, app and db -> local only ..."
rt_public=$(route_table rt-public "$public_a" "$public_b")
rt_app=$(route_table rt-app "$app_a" "$app_b")
rt_db=$(route_table rt-db "$db_a" "$db_b")
save_state "$LAB" ROUTE_TABLE_IDS "$rt_public $rt_app $rt_db"
ec2 create-route --route-table-id "$rt_public" --destination-cidr-block 0.0.0.0/0 \
  --gateway-id "$igw" >/dev/null

security_group() {   # security_group <name> <description>; prints the group id
  ec2 create-security-group --vpc-id "$vpc" --group-name "$(name "$1")" --description "$2" \
    --tag-specifications "$(tag_spec security-group "$LAB" "$(name "$1")")" \
    --query GroupId --output text
}
log "Creating security groups: lb (443 from anywhere), app (8000 from lb), db (5432 from app) ..."
sg_lb=$(security_group sg-lb "Load balancer, lab $LAB")
sg_app=$(security_group sg-app "PlaceFinder containers, lab $LAB")
sg_db=$(security_group sg-db "PostgreSQL, lab $LAB")
save_state "$LAB" SECURITY_GROUP_IDS "$sg_lb $sg_app $sg_db"
ec2 authorize-security-group-ingress --group-id "$sg_lb" --protocol tcp --port 443 \
  --cidr 0.0.0.0/0 >/dev/null
ec2 authorize-security-group-ingress --group-id "$sg_app" --protocol tcp --port 8000 \
  --source-group "$sg_lb" >/dev/null
ec2 authorize-security-group-ingress --group-id "$sg_db" --protocol tcp --port 5432 \
  --source-group "$sg_app" >/dev/null

if $with_nat; then
  warn "The NAT gateway costs about 0.045 USD per hour plus data. Delete it today!"
  eip=$(ec2 allocate-address --domain vpc \
    --tag-specifications "$(tag_spec elastic-ip "$LAB" "$(name nat-ip)")" \
    --query AllocationId --output text)
  save_state "$LAB" EIP_ALLOCATION_ID "$eip"
  nat=$(ec2 create-nat-gateway --subnet-id "$public_a" --allocation-id "$eip" \
    --tag-specifications "$(tag_spec natgateway "$LAB" "$(name nat)")" \
    --query NatGateway.NatGatewayId --output text)
  save_state "$LAB" NAT_GATEWAY_ID "$nat"
  log "Waiting for NAT gateway $nat ..."
  ec2 wait nat-gateway-available --nat-gateway-ids "$nat"
  ec2 create-route --route-table-id "$rt_app" --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id "$nat" >/dev/null
  save_state "$LAB" NAT true
fi

if $with_vm; then
  ip=$(my_ip)
  key=$(ensure_key_pair "$LAB")
  ami=$(ubuntu_ami amd64)
  log "Creating security groups for SSH: bastion (22 from $ip), private VM (22 from the bastion) ..."
  sg_ssh=$(security_group sg-ssh "SSH from my IP, lab $LAB")
  sg_ssh_bastion=$(security_group sg-ssh-from-bastion "SSH from the bastion, lab $LAB")
  save_state "$LAB" SSH_SECURITY_GROUP_IDS "$sg_ssh $sg_ssh_bastion"
  ec2 authorize-security-group-ingress --group-id "$sg_ssh" --protocol tcp --port 22 \
    --cidr "$ip/32" >/dev/null
  ec2 authorize-security-group-ingress --group-id "$sg_ssh_bastion" --protocol tcp --port 22 \
    --source-group "$sg_ssh" >/dev/null

  vm() {   # vm <name> <subnet> <public address flag> <security groups...>; prints the instance id
    ec2 run-instances --image-id "$ami" --instance-type t3.micro --key-name "$key" \
      --subnet-id "$2" "$3" --security-group-ids "${@:4}" \
      --metadata-options HttpTokens=required \
      --tag-specifications "$(tag_spec instance "$LAB" "$(name "$LAB-$1")")" \
      --query 'Instances[0].InstanceId' --output text
  }
  log "Creating the bastion in public-a and a private VM in app-a ..."
  bastion=$(vm bastion "$public_a" --associate-public-ip-address "$sg_ssh")
  private=$(vm private "$app_a" --no-associate-public-ip-address "$sg_app" "$sg_ssh_bastion")
  save_state "$LAB" INSTANCE_IDS "$bastion $private"
  ec2 wait instance-running --instance-ids "$bastion" "$private"
  bastion_ip=$(ec2 describe-instances --instance-ids "$bastion" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  private_ip=$(ec2 describe-instances --instance-ids "$private" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  save_state "$LAB" SSH_USER ubuntu
  save_state "$LAB" BASTION_IP "$bastion_ip"
  save_state "$LAB" PRIVATE_IP "$private_ip"
  log "Bastion:    ssh ubuntu@$bastion_ip"
  log "Private VM: ssh -J ubuntu@$bastion_ip ubuntu@$private_ip"
  log "Check both: ./check-vpc.sh (the VMs need about a minute to start SSH)"
fi

log "Network created. Overview:"
# shellcheck disable=SC2016  # backticks are JMESPath literals
ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" \
  --query 'Subnets[].[Tags[?Key==`Name`]|[0].Value,CidrBlock,AvailabilityZone,AvailableIpAddressCount]' \
  --output table
log "Delete everything with ./destroy-vpc.sh"
