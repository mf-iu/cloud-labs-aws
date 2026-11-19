output "function_name" {
  value = aws_lambda_function.sync.function_name
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "bucket" {
  description = "Bucket of base; the change files are under geonames/changes/"
  value       = local.bucket
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "log_group" {
  value = aws_cloudwatch_log_group.function.name
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

output "dead_letter_queue" {
  description = "URL of the dead-letter queue (extra task); empty without it"
  value       = var.dead_letter ? aws_sqs_queue.dead_letter[0].url : ""
}
