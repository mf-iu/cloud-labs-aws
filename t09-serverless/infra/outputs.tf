output "function_name" {
  value = aws_lambda_function.sync.function_name
}

output "bucket" {
  value = aws_s3_bucket.data.bucket
}

output "log_group" {
  value = aws_cloudwatch_log_group.function.name
}
