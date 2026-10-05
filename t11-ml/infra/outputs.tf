locals {
  endpoint = [
    for path in aws_ecs_express_gateway_service.estimate.ingress_paths :
    path.endpoint if path.access_type == "PUBLIC"
  ][0]
}

output "service_url" {
  value = startswith(local.endpoint, "http") ? local.endpoint : "https://${local.endpoint}"
}

output "bucket" {
  value = aws_s3_bucket.ml.bucket
}

output "model_uri" {
  value = "s3://${aws_s3_bucket.ml.bucket}/${var.model_key}"
}

output "mlflow_artifacts_destination" {
  value = "s3://${aws_s3_bucket.ml.bucket}/mlflow"
}
