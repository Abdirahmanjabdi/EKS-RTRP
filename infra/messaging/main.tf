terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "rtrp-terraform-state-04b6152c"
    key            = "messaging/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "vpc/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "terraform_remote_state" "ecs" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "ecs/terraform.tfstate"
    region = "eu-north-1"
  }
}

# 1. Broker credentials — generated, never hardcoded. Amazon MQ disallows
# commas in the password, so the special-character set is restricted rather
# than disabled outright.
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

# 2. Security Group (Allows AMQPS only, only from ECS tasks — Amazon MQ for
# RabbitMQ enforces TLS and only exposes port 5671, unlike self-hosted
# RabbitMQ's default unencrypted 5672)
resource "aws_security_group" "rabbitmq" {
  name        = "${var.project_name}-rabbitmq-sg"
  description = "Allow AMQPS from ECS tasks only"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description     = "AMQPS from ECS tasks"
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [data.terraform_remote_state.ecs.outputs.ecs_tasks_security_group_id]
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

# 3. Amazon MQ Broker (single-instance RabbitMQ — see ADR-002.
# mq.t3.micro is deprecated for new brokers; mq.m7g.medium is the smallest
# instance type AWS currently allows for a new RabbitMQ broker)
resource "aws_mq_broker" "rabbitmq" {
  broker_name = "${var.project_name}-rabbitmq"

  engine_type        = "RabbitMQ"
  engine_version     = "4.2"
  host_instance_type = "mq.m7g.medium"
  deployment_mode    = "SINGLE_INSTANCE"
  storage_type       = "ebs"

  publicly_accessible = false
  subnet_ids          = [data.terraform_remote_state.vpc.outputs.private_subnet_ids[0]]
  security_groups     = [aws_security_group.rabbitmq.id]
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
