# PlaceFinder on Amazon ECS Express Mode (Fargate with HTTPS load balancer).
# The service runs in the default VPC like in lab t03.

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
  name               = "${local.name}-t08-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "infrastructure" {
  name               = "${local.name}-t08-ecs-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.ecs.json
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

resource "aws_ecs_express_gateway_service" "placefinder" {
  service_name            = "${local.name}-t08-placefinder"
  execution_role_arn      = aws_iam_role.execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  cpu                     = "256"
  memory                  = "512"
  health_check_path       = "/health"
  wait_for_steady_state   = true

  primary_container {
    image          = "${var.placefinder_image}:${var.image_tag}"
    container_port = 8000

    environment {
      name  = "DATA_BUCKET"
      value = aws_s3_bucket.data.bucket
    }
  }

  scaling_target {
    min_task_count = 1
    max_task_count = 2
  }

  # The roles must exist until the service is deleted completely
  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy_attachment.infrastructure,
  ]
}
