variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the ALB, ECS tasks, and their security groups into"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs for the ALB"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the ECS tasks"
}

variable "rabbitmq_amqps_endpoint" {
  type        = string
  description = "AMQPS URL of the RabbitMQ broker, injected as a plain (non-secret) container environment variable"
}

variable "rabbitmq_credentials_secret_arn" {
  type        = string
  description = "Secrets Manager ARN holding RabbitMQ username/password, injected into containers via the ECS execution role"
}

variable "postgres_host" {
  type = string
}
variable "postgres_port" {
  type = string
}
variable "postgres_db" {
  type = string
}
variable "postgres_credentials_secret_arn" {
  type = string
}
variable "redis_host" {
  type = string
}
variable "redis_port" {
  type = string
}
variable "redis_auth_token_secret_arn" {
  type = string
}
