#!/usr/bin/env bash
# Create an EC2 VM that installs and runs PlaceFinder via cloud-init.
# Usage: ./create-vm.sh [git ref]   (default ref: t01)
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/provider.sh"

LAB=t02
ref="${1:-t01}"
instance_type="${VM_TYPE:-t3.micro}"
check_login
check_repo_ref "$PLACEFINDER_REPO" "$ref"
load_state "$LAB"
[[ -z "${INSTANCE_ID:-}" ]] || die "VM $INSTANCE_ID already exists. Run ./destroy-vm.sh first."

ip=$(my_ip)
vpc=$(default_vpc)
key=$(ensure_key_pair "$LAB")

log "Creating security group (SSH and port 8000 from $ip only) ..."
sg_name=$(name "$LAB-vm")
sg=$(aws ec2 create-security-group --group-name "$sg_name" --vpc-id "$vpc" \
  --description "PlaceFinder VM, lab $LAB" \
  --tag-specifications "$(tag_spec security-group "$LAB" "$sg_name")" \
  --query GroupId --output text)
save_state "$LAB" SECURITY_GROUP_ID "$sg"
aws ec2 authorize-security-group-ingress --group-id "$sg" --ip-permissions \
  "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$ip/32,Description=ssh-from-my-ip}]" \
  "IpProtocol=tcp,FromPort=8000,ToPort=8000,IpRanges=[{CidrIp=$ip/32,Description=api-from-my-ip}]" \
  >/dev/null

user_data=$(mktemp)
trap 'rm -f "$user_data"' EXIT
render "$(dirname "$0")/cloud-init.yaml" "REPO=$PLACEFINDER_REPO" "REF=$ref" >"$user_data"

vm_name=$(name "$LAB-vm")
log "Starting $instance_type with Ubuntu 24.04 ..."
instance=$(aws ec2 run-instances \
  --image-id "$(ubuntu_ami amd64)" \
  --instance-type "$instance_type" \
  --key-name "$key" \
  --security-group-ids "$sg" \
  --user-data "file://$user_data" \
  --metadata-options HttpTokens=required \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=10,VolumeType=gp3,DeleteOnTermination=true}' \
  --tag-specifications "$(tag_spec instance "$LAB" "$vm_name")" "$(tag_spec volume "$LAB" "$vm_name")" \
  --query 'Instances[0].InstanceId' --output text)
save_state "$LAB" INSTANCE_ID "$instance"

aws ec2 wait instance-running --instance-ids "$instance"
public_ip=$(aws ec2 describe-instances --instance-ids "$instance" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save_state "$LAB" PUBLIC_IP "$public_ip"

cat <<INFO

VM $instance is running.
  SSH:          ssh ubuntu@$public_ip
  cloud-init:   ssh ubuntu@$public_ip cloud-init status --wait
  API:          http://$public_ip:8000/places?q=Erfurt
  Delete:       ./destroy-vm.sh
INFO
wait_for_http "http://$public_ip:8000/health" 600 || warn "Check the log on the VM: journalctl -u placefinder"
