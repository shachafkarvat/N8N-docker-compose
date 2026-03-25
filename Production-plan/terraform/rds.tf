resource "aws_db_subnet_group" "n8n" {
  name       = "n8n-db-subnets"
  subnet_ids = var.private_subnet_ids
}

resource "aws_db_instance" "n8n" {
  identifier                = "n8n-postgres"
  engine                    = "postgres"
  engine_version            = "16"
  instance_class            = "db.t4g.micro"
  allocated_storage         = 30
  name                      = var.db_name
  username                  = var.db_username
  password                  = data.aws_ssm_parameter.db_password.value
  vpc_security_group_ids    = [aws_security_group.rds_sg.id]
  db_subnet_group_name      = aws_db_subnet_group.n8n.name
  backup_retention_period   = 7
  skip_final_snapshot       = true
  multi_az                  = false
  publicly_accessible       = false
}
