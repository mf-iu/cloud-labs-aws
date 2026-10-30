# Read by service (terraform_remote_state) and later configurations

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "vpc_id" {
  value = aws_vpc.main.id
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "subnet_ids" {
  description = "Subnet ids by tier: public, app, db"
  value       = local.subnet_ids
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "public_subnet_cidrs" {
  description = "Address ranges of the public subnets, where the service runs"
  value       = [for key, s in local.subnets : s.cidr if s.tier == "public"]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "bucket" {
  value = aws_s3_bucket.data.bucket
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "execution_role_name" {
  value = aws_iam_role.execution.name
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "infrastructure_role_arn" {
  value = aws_iam_role.infrastructure.arn
}
