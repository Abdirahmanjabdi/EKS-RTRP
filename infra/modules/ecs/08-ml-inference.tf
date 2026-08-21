resource "aws_cloudwatch_log_group" "ml_inference" {
  name              = "/ecs/${var.project_name}-ml-inference"
  retention_in_days = 7
}

resource "aws_security_group" "ml_inference" {
  name        = "${var.project_name}-ml-inference-sg"
  description = "ML Inference: outbound only, no inbound access permitted"
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound traffic for RabbitMQ and AWS API access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Metrics scraping from Prometheus"
    from_port       = 8002
    to_port         = 8002
    protocol        = "tcp"
    security_groups = [aws_security_group.prometheus.id]
  }

  tags = { Name = "${var.project_name}-ml-inference-sg" }
}

resource "aws_service_discovery_service" "ml_inference" {
  name = "ml-inference"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_task_definition" "ml_inference" {
  family                   = "${var.project_name}-ml-inference"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "ml-inference"
    image     = "026703081738.dkr.ecr.eu-north-1.amazonaws.com/rtrp-ml-inference:v0"
    essential = true
    environment = [
      { name = "RABBITMQ_URL", value = var.rabbitmq_amqps_endpoint },
      { name = "POSTGRES_HOST", value = var.postgres_host },
      { name = "POSTGRES_PORT", value = var.postgres_port },
      { name = "POSTGRES_DB", value = var.postgres_db },
      { name = "REDIS_HOST", value = var.redis_host },
      { name = "REDIS_PORT", value = var.redis_port }
    ]
    secrets = [
      { name = "RABBITMQ_USERNAME", valueFrom = "${var.rabbitmq_credentials_secret_arn}:username::" },
      { name = "RABBITMQ_PASSWORD", valueFrom = "${var.rabbitmq_credentials_secret_arn}:password::" },
      { name = "POSTGRES_USER", valueFrom = "${var.postgres_credentials_secret_arn}:username::" },
      { name = "POSTGRES_PASSWORD", valueFrom = "${var.postgres_credentials_secret_arn}:password::" },
      { name = "REDIS_AUTH_TOKEN", valueFrom = var.redis_auth_token_secret_arn }
    ]
    portMappings = [{
      containerPort = 8002
      hostPort      = 8002
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ml_inference.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ml-inference"
      }
    }
  }])
}

resource "aws_ecs_service" "ml_inference" {
  name            = "${var.project_name}-ml-inference-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ml_inference.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ml_inference.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.ml_inference.arn
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_iam_role_policy_attachment.execution]
}