# 1. CloudWatch Log Group for Risk Engine container logging
resource "aws_cloudwatch_log_group" "risk_engine" {
  name              = "/ecs/${var.project_name}-risk-engine"
  retention_in_days = 7
}

# 2. Security Group — zero ingress rules. Risk Engine only ever opens
# outbound connections (RabbitMQ, AWS APIs via NAT); nothing should be able
# to reach it, so that's enforced here rather than left true by accident.
resource "aws_security_group" "risk_engine" {
  name        = "${var.project_name}-risk-engine-sg"
  description = "Risk Engine: outbound only, no inbound access permitted"
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
    from_port       = 8001
    to_port         = 8001
    protocol        = "tcp"
    security_groups = [aws_security_group.prometheus.id]
  }

  tags = { Name = "${var.project_name}-risk-engine-sg" }
}

# 3. ECS Task Definition
resource "aws_ecs_task_definition" "risk_engine" {
  family                   = "${var.project_name}-risk-engine"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "risk-engine"
    image     = "026703081738.dkr.ecr.eu-north-1.amazonaws.com/rtrp-risk-engine:v0"
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
      containerPort = 8001
      hostPort      = 8001
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.risk_engine.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "risk-engine"
      }
    }
  }])
}

# 4. ECS Service — no load_balancer block, unlike trade_api's service: a
# background worker has no inbound traffic to register with a target group.
resource "aws_ecs_service" "risk_engine" {
  name            = "${var.project_name}-risk-engine-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.risk_engine.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.risk_engine.id]
    assign_public_ip = false
  }
  
  lifecycle {
    ignore_changes = [task_definition]
  }

    service_registries {
    registry_arn = aws_service_discovery_service.risk_engine.arn
  }

  
  depends_on = [
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_secrets
  ]
}
