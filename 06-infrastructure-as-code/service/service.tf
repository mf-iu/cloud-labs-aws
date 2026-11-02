# PlaceFinder on Amazon Elastic Container Service (ECS) Express Mode (Fargate
# with HTTPS load balancer) as in session 3, now in the public subnets of the
# Virtual Private Cloud (VPC) of base. With public subnets, Express Mode creates
# an internet-facing load balancer and gives the tasks public IP addresses, so
# they can pull the image from ghcr.io.
# The Continuous Integration (CI) pipeline of PlaceFinder pushes the images
# there; the deploy workflow (deploy.example.yml) rolls out new versions.

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

locals {
  # with a database: connection string without password, the password comes
  # from the secret as PGPASSWORD (libpq reads it); DATABASE_INIT loads the
  # places from the image into the empty database (PlaceFinder from t08)
  database_env = var.enable_database ? {
    DATABASE_URL  = "postgresql://${aws_db_instance.db[0].username}@${aws_db_instance.db[0].endpoint}/placefinder?sslmode=require"
    DATABASE_INIT = "true"
  } : {}
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

resource "aws_ecs_express_gateway_service" "placefinder" {
  service_name            = "${local.name}-t08-placefinder"
  execution_role_arn      = local.base.execution_role_arn
  infrastructure_role_arn = local.base.infrastructure_role_arn
  cpu                     = "256"
  memory                  = "512"
  health_check_path       = "/health"
  wait_for_steady_state   = true

  network_configuration {
    subnets = local.base.subnet_ids["public"]
  }

  primary_container {
    image          = "${var.placefinder_image}:${var.image_tag}"
    container_port = 8000

    dynamic "environment" {
      for_each = local.database_env
      content {
        name  = environment.key
        value = environment.value
      }
    }

    # the key "password" of the secret that Relational Database Service (RDS)
    # manages (database.tf)
    dynamic "secret" {
      for_each = var.enable_database ? [1] : []
      content {
        name       = "PGPASSWORD"
        value_from = "${aws_db_instance.db[0].master_user_secret[0].secret_arn}:password::"
      }
    }
  }

  scaling_target {
    min_task_count = 1
    max_task_count = var.max_tasks
  }

  # The deploy workflow sets new images; without this, the next apply would
  # roll back to image_tag (drift between pipeline and OpenTofu)
  lifecycle {
    ignore_changes = [primary_container[0].image]
  }

  # The execution role must be able to read the secret before the first task
  depends_on = [aws_iam_role_policy.read_db_secret]
}
