# Optional PostgreSQL (enable_database = true) in the database subnets: no
# public address, reachable only from the subnets of the service. Unlike
# session 6, it cannot be loaded from your computer; PlaceFinder loads the
# places itself at startup (DATABASE_INIT, service.tf).

resource "aws_db_subnet_group" "db" {
  count      = var.enable_database ? 1 : 0
  name       = "${local.name}-t08-db"
  subnet_ids = local.subnet_ids["db"]
}

resource "aws_security_group" "db" {
  count       = var.enable_database ? 1 : 0
  name        = "${local.name}-t08-db"
  description = "PostgreSQL from the subnets of the service"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [for key, s in local.subnets : s.cidr if s.tier == "public"]
  }
}

resource "aws_db_instance" "db" {
  count                  = var.enable_database ? 1 : 0
  identifier             = "${local.name}-t08-db"
  engine                 = "postgres"
  engine_version         = "18" # the current minor version, as in session 6
  instance_class         = "db.t4g.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  db_name                = "placefinder"
  username               = "pfadmin"
  db_subnet_group_name   = aws_db_subnet_group.db[0].name
  vpc_security_group_ids = [aws_security_group.db[0].id]
  publicly_accessible    = false

  # RDS creates the password and keeps it in Secrets Manager: it never
  # appears in the configuration or in the OpenTofu state
  manage_master_user_password = true

  backup_retention_period = 1
  skip_final_snapshot     = true # lab only
  deletion_protection     = false
  apply_immediately       = true
}

# The execution role may read exactly this secret
resource "aws_iam_role_policy" "read_db_secret" {
  count = var.enable_database ? 1 : 0
  name  = "read-db-secret"
  role  = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.db[0].master_user_secret[0].secret_arn
    }]
  })
}
