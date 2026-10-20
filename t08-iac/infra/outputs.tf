locals {
  endpoint = one([
    for path in aws_ecs_express_gateway_service.placefinder.ingress_paths :
    path.endpoint if path.access_type == "PUBLIC"
  ])
}

output "service_url" {
  description = "HTTPS endpoint of PlaceFinder"
  value       = startswith(local.endpoint, "http") ? local.endpoint : "https://${local.endpoint}"
}

output "service_arn" {
  description = "For the deploy workflow (repository variable SERVICE_ARN)"
  value       = aws_ecs_express_gateway_service.placefinder.service_arn
}

output "bucket" {
  value = aws_s3_bucket.data.bucket
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "database" {
  description = "Host and port of PostgreSQL (only with enable_database = true)"
  value       = var.enable_database ? aws_db_instance.db[0].endpoint : null
}
