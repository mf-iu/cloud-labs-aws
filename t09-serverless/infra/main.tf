# Daily GeoNames update as AWS Lambda function, started by EventBridge
# Scheduler. Build the package first: ../package.sh

locals {
  name = "${var.prefix}-${var.owner}-t09"
}

# Bucket for the change files
resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-${var.suffix}-data"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/../build"
  output_path = "${path.module}/../build.zip"
}

# Execution role: write logs, write objects into the bucket, nothing else
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "function" {
  name               = "${local.name}-geonames-sync"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.function.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/geonames/*"]
  }
}

resource "aws_iam_role_policy" "bucket" {
  name   = "write-change-files"
  role   = aws_iam_role.function.id
  policy = data.aws_iam_policy_document.bucket.json
}

resource "aws_cloudwatch_log_group" "function" {
  name              = "/aws/lambda/${local.name}-geonames-sync"
  retention_in_days = 7
}

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
      DATA_BUCKET  = aws_s3_bucket.data.bucket
      DATABASE_URL = var.database_url
    }
  }

  depends_on = [aws_cloudwatch_log_group.function, aws_iam_role_policy_attachment.logs]
}

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

resource "aws_iam_role" "scheduler" {
  name               = "${local.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_trust.json
}

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
