# 1. Broker credentials — generated, never hardcoded. Amazon MQ rejects
# commas in passwords, so special chars are restricted, not turned off.
resource "random_password" "rabbitmq" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "rabbitmq" {
  name = "${var.project_name}-rabbitmq-credentials"
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  secret_id = aws_secretsmanager_secret.rabbitmq.id
  secret_string = jsonencode({
    username = var.rabbitmq_username
    password = random_password.rabbitmq.result
  })
}

# 2. Security Group — AMQPS only, from ECS tasks only. Amazon MQ enforces
# TLS and only exposes 5671, unlike self-hosted RabbitMQ's default 5672.
resource "aws_security_group" "rabbitmq" {
  name        = "${var.project_name}-rabbitmq-sg"
  description = "Allow AMQPS from ECS tasks only"
  vpc_id      = var.vpc_id

  ingress {
    description = "AMQPS from Trade API and Risk Engine tasks"
    from_port   = 5671
    to_port     = 5671
    protocol    = "tcp"
    security_groups = [
      var.ecs_tasks_security_group_id,
      var.risk_engine_security_group_id,
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-rabbitmq-sg" }
}

# 3. Amazon MQ Broker — single-instance, see ADR-002. mq.t3.micro is
# deprecated for new brokers; mq.m7g.medium is the smallest size available now.
resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${var.project_name}-rabbitmq"

  engine_type        = "RabbitMQ"
  engine_version     = "4.2"
  host_instance_type = "mq.m7g.medium"
  deployment_mode    = "SINGLE_INSTANCE"
  storage_type       = "ebs"

  publicly_accessible        = false
  subnet_ids                 = [var.private_subnet_ids[0]]
  security_groups             = [aws_security_group.rabbitmq.id]
  auto_minor_version_upgrade = true

  user {
    username = var.rabbitmq_username
    password = random_password.rabbitmq.result
  }

  logs {
    general = true
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
