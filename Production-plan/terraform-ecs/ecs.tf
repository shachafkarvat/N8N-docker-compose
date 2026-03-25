resource "aws_ecs_cluster" "n8n" {
  name = "n8n-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.tags
}

resource "aws_ecs_task_definition" "n8n" {
  family                   = "n8n"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu    # 1024 = 1 vCPU
  memory                   = var.ecs_task_memory # 4096 = 4 GB hard task limit
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "n8n"
      image     = "docker.n8n.io/n8nio/n8n:stable"
      essential = true

      portMappings = [
        { containerPort = 5678, hostPort = 5678, protocol = "tcp" }
      ]

      # Soft memory limit — allows bursting up to the task-level hard limit (4096 MB)
      memoryReservation = 2048

      environment = [
        { name = "N8N_HOST",               value = local.fqdn },
        { name = "N8N_PORT",               value = "5678" },
        { name = "N8N_PROTOCOL",           value = "https" },
        { name = "WEBHOOK_URL",            value = "https://${local.fqdn}/" },
        { name = "NODE_ENV",               value = "production" },
        { name = "DB_TYPE",                value = "postgresdb" },
        { name = "DB_POSTGRESDB_HOST",     value = aws_db_instance.n8n.address },
        { name = "DB_POSTGRESDB_PORT",     value = "5432" },
        { name = "DB_POSTGRESDB_DATABASE", value = var.db_name },
        { name = "DB_POSTGRESDB_USER",     value = var.db_username },
        # Critical: tells n8n to trust one proxy hop (the ALB) for X-Forwarded headers
        { name = "N8N_PROXY_HOPS",         value = "1" },
        { name = "GENERIC_TIMEZONE",       value = var.timezone },
        { name = "N8N_RUNNERS_ENABLED",    value = "true" },
        # Cap Node.js heap at 3 GB — leaves ~1 GB headroom within the 4 GB task limit
        { name = "NODE_OPTIONS",           value = "--max-old-space-size=3072" },
        { name = "N8N_LOG_LEVEL",          value = "info" },
        { name = "N8N_LOG_OUTPUT",         value = "console" }
        # NODE_FUNCTION_ALLOW_EXTERNAL=cheerio intentionally omitted:
        # cheerio requires a custom Docker image (n8n.Dockerfile). See ecr_note output.
      ]

      # Secrets are injected by the execution role at container startup via SSM
      secrets = [
        { name = "DB_POSTGRESDB_PASSWORD", valueFrom = aws_ssm_parameter.db_password.arn },
        { name = "N8N_ENCRYPTION_KEY",     valueFrom = aws_ssm_parameter.encryption_key.arn }
      ]

      mountPoints = [
        {
          sourceVolume  = "n8n-efs"
          containerPath = "/home/node/.n8n"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.n8n.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  volume {
    name = "n8n-efs"
    efs_volume_configuration {
      file_system_id          = aws_efs_file_system.n8n.id
      transit_encryption      = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.n8n.id
        iam             = "ENABLED"
      }
    }
  }

  tags = local.tags
}

resource "aws_ecs_service" "n8n" {
  name                              = "n8n-service"
  cluster                           = aws_ecs_cluster.n8n.id
  task_definition                   = aws_ecs_task_definition.n8n.arn
  desired_count                     = 1
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 60

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

  # Ensure the HTTPS listener exists before the service registers targets
  depends_on = [aws_lb_listener.https]

  tags = local.tags
}
