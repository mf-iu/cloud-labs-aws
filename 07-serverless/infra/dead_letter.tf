# Extra task (-var dead_letter=true): a dead-letter queue for runs that still
# fail after the retries, and an alarm as soon as it is not empty. Without
# the variable, count = 0 creates none of these resources.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_sqs_queue" "dead_letter" {
  count                     = var.dead_letter ? 1 : 0
  name                      = "${local.name}-geonames-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Lambda sends failed events with the execution role of the function
resource "aws_iam_role_policy" "dead_letter" {
  count = var.dead_letter ? 1 : 0
  name  = "send-to-dead-letter-queue"
  role  = aws_iam_role.function.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.dead_letter[0].arn
    }]
  })
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Notification by e-mail; AWS sends a confirmation link first
resource "aws_sns_topic" "alarm" {
  count = var.dead_letter && var.alert_email != "" ? 1 : 0
  name  = "${local.name}-geonames-alarm"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_sns_topic_subscription" "alarm" {
  count     = var.dead_letter && var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarm[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Alarm when at least one message waits in the dead-letter queue
resource "aws_cloudwatch_metric_alarm" "dead_letter" {
  count               = var.dead_letter ? 1 : 0
  alarm_name          = "${local.name}-geonames-dlq-not-empty"
  alarm_description   = "A GeoNames update failed after all retries"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letter[0].name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = aws_sns_topic.alarm[*].arn
}
