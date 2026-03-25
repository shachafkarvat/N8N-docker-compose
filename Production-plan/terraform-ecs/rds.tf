resource "aws_db_subnet_group" "n8n" {
  name        = "n8n-db-subnets"
  description = "Private subnets for n8n RDS instance"
  subnet_ids  = var.private_subnet_ids
  tags        = local.tags
}

resource "aws_db_instance" "n8n" {
  identifier     = "n8n-postgres"
  engine         = "postgres"
  engine_version = "16.4"
  instance_class = "db.t4g.micro"

  db_name  = var.db_name
  username = var.db_username
  password = aws_ssm_parameter.db_password.value

  allocated_storage = 30
  storage_type      = "gp3"
  storage_encrypted = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.n8n.name

  # RDS automated snapshots retained for 7 days (complements AWS Backup)
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Sun:04:00-Sun:05:00"

  multi_az               = false # Single-AZ for cost optimisation
  publicly_accessible    = false
  deletion_protection    = false

  # Retain a final snapshot when this resource is destroyed
  skip_final_snapshot       = false
  final_snapshot_identifier = "n8n-postgres-final-snapshot"

  tags = local.tags
}
