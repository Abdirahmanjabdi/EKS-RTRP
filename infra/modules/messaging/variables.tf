variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "rabbitmq_username" {
  type        = string
  description = "Administrative username for the RabbitMQ broker"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the broker's security group into"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs; the broker uses the first one (single-instance, no HA)"
}

variable "ecs_tasks_security_group_id" {
  type        = string
  description = "Trade API's ECS tasks security group ID, allowed to reach the broker"
}

variable "risk_engine_security_group_id" {
  type        = string
  description = "Risk Engine's ECS tasks security group ID, allowed to reach the broker"
}
