resource "aws_ecs_cluster" "n8n" {
  name = "n8n-cluster"
}

resource "aws_ecs_task_definition" "n8n" {
  family                   = "n8n"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "n8n"
      image     = "docker.n8n.io/n8nio/n8n:stable"
      portMappings = [{ containerPort = 5678, hostPort = 5678 }]
      environment = [
        { name = "N8N_HOST", value = local.fqdn },
        { name = "N8N_PORT", value = "5678" },
        { name = "N8N_PROTOCOL", value = "https" },
        { name = "WEBHOOK_URL", value = "https://${local.fqdn}/" },
        { name = "DB_TYPE", value = "postgresdb" },
        { name = "DB_POSTGRESDB_HOST", value = aws_db_instance.n8n.address },
        { name = "DB_POSTGRESDB_DATABASE", value = var.db_name },
        { name = "DB_POSTGRESDB_USER", value = var.db_username }
      ]
      secrets = [
        { name = "DB_POSTGRESDB_PASSWORD", valueFrom = var.db_password_ssm_param },
        { name = "N8N_ENCRYPTION_KEY", valueFrom = var.n8n_encryption_key_ssm_param }
      ]
      mountPoints = [
        { sourceVolume = "n8n-efs", containerPath = "/home/node/.n8n" }
      ]
    }
  ])

  volume {
    name = "n8n-efs"
    efs_volume_configuration {
      file_system_id = aws_efs_file_system.n8n.id
    }
  }
}

resource "aws_ecs_service" "n8n" {
  name            = "n8n-service"
  cluster         = aws_ecs_cluster.n8n.id
  task_definition = aws_ecs_task_definition.n8n.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.n8n.arn
    container_name   = "n8n"
    container_port   = 5678
  }
}
