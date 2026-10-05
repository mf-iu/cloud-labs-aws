# Optional PostgreSQL (enable_database = true). Reachable only from
# admin_cidrs; connecting the service is part of the exercise (README).

resource "random_password" "db" {
  count   = var.enable_database ? 1 : 0
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "db" {
  count      = var.enable_database ? 1 : 0
  name       = "${local.name}-t08-db"
  subnet_ids = [for key in ["public-a", "public-b"] : aws_subnet.this[key].id]
}

resource "aws_security_group" "db" {
  count       = var.enable_database ? 1 : 0
  name        = "${local.name}-t08-db"
  description = "PostgreSQL from admin networks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }
}

resource "aws_db_instance" "db" {
  count                   = var.enable_database ? 1 : 0
  identifier              = "${local.name}-t08-db"
  engine                  = "postgres"
  instance_class          = "db.t4g.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  db_name                 = "placefinder"
  username                = "pfadmin"
  password                = random_password.db[0].result
  db_subnet_group_name    = aws_db_subnet_group.db[0].name
  vpc_security_group_ids  = [aws_security_group.db[0].id]
  publicly_accessible     = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
}
