# Lab t11: bucket for MLflow artifacts and models, PlaceFinder with the
# /estimate endpoint on ECS Express Mode. The task role may read the model.

locals {
  name = "${var.prefix}-${var.owner}-t11"
}

resource "aws_s3_bucket" "ml" {
  bucket        = "${local.name}-${var.suffix}-ml"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "ml" {
  bucket                  = aws_s3_bucket.ml.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "infrastructure" {
  name               = "${local.name}-ecs-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.ecs.json
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

# Task role: the application itself may only read the models
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks.json
}

resource "aws_iam_role_policy" "task" {
  name = "read-models"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.ml.arn}/models/*"
    }]
  })
}

resource "aws_ecs_express_gateway_service" "estimate" {
  service_name            = "${local.name}-estimate"
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  task_role_arn           = aws_iam_role.task.arn
  cpu                     = "512"
  memory                  = "1024"
  health_check_path       = "/health"
  wait_for_steady_state   = true

  primary_container {
    image          = "${var.placefinder_image}:${var.image_tag}"
    container_port = 8000

    environment {
      name  = "MODEL_URI"
      value = "s3://${aws_s3_bucket.ml.bucket}/${var.model_key}"
    }
  }

  scaling_target {
    min_task_count = 1
    max_task_count = 2
  }

  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy_attachment.infrastructure,
  ]
}
