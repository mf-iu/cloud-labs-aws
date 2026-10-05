locals {
  endpoint = [
    for path in aws_ecs_express_gateway_service.placefinder.ingress_paths :
    path.endpoint if path.access_type == "PUBLIC"
  ][0]
}

output "service_url" {
  description = "HTTPS endpoint of PlaceFinder"
  value       = startswith(local.endpoint, "http") ? local.endpoint : "https://${local.endpoint}"
}

output "bucket" {
  value = aws_s3_bucket.data.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.placefinder.repository_url
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "database_url" {
  description = "Connection string (only with enable_database = true)"
  value = var.enable_database ? format("postgresql://pfadmin:%s@%s/placefinder?sslmode=require",
  random_password.db[0].result, aws_db_instance.db[0].endpoint) : null
  sensitive = true
}

output "service_arn" {
  value = aws_ecs_express_gateway_service.placefinder.service_arn
}
