# Daily GeoNames update as AWS Lambda function, started by EventBridge
# Scheduler. Build the package first: 07-serverless/package.sh

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/../build"
  output_path = "${path.module}/../build.zip"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Execution role: write logs, write objects under geonames/ in the bucket of
# base, nothing else
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_iam_role" "function" {
  name               = "${local.name}-geonames-sync"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

data "aws_iam_policy_document" "bucket" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${local.bucket}/geonames/*"]
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_iam_role_policy" "bucket" {
  name   = "write-change-files"
  role   = aws_iam_role.function.id
  policy = data.aws_iam_policy_document.bucket.json
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.name}-geonames-sync"
  retention_in_days = 7
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_lambda_function" "sync" {
  function_name    = "${local.name}-geonames-sync"
  role             = aws_iam_role.function.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      DATA_BUCKET  = local.bucket
      DATABASE_URL = var.database_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.function, aws_iam_role_policy_attachment.logs]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Asynchronous calls (the schedule, invoke.sh --async): Lambda retries a failed
# run twice, after about one and two more minutes. With the extra task, an
# event that still fails goes to the dead-letter queue (dead_letter.tf).
resource "aws_lambda_function_event_invoke_config" "sync" {
  function_name                = aws_lambda_function.sync.function_name
  maximum_retry_attempts       = 2
  maximum_event_age_in_seconds = 3600

  dynamic "destination_config" {
    for_each = var.dead_letter ? [1] : []
    content {
      on_failure {
        destination = aws_sqs_queue.dead_letter[0].arn
      }
    }
  }

  depends_on = [aws_iam_role_policy.dead_letter]
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# EventBridge Scheduler may invoke exactly this function
data "aws_iam_policy_document" "scheduler_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_iam_role_policy" "scheduler" {
  name = "invoke-function"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.sync.arn
    }]
  })
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# The scheduler hands the event to Lambda asynchronously. Its own retries only
# cover the delivery (e.g. throttling); a failing run is retried by Lambda.
resource "aws_scheduler_schedule" "daily" {
  name                         = "${local.name}-geonames-daily"
  schedule_expression          = var.schedule
  schedule_expression_timezone = "Europe/Berlin"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.sync.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}
