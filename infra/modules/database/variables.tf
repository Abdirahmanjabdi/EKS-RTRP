variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the DB subnet group and security group into"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the DB subnet group"
}

variable "ecs_tasks_security_group_id" {
  type        = string
  description = "Trade API's ECS tasks security group ID, allowed to reach Postgres"
}

variable "risk_engine_security_group_id" {
  type        = string
  description = "Risk Engine's ECS tasks security group ID, allowed to reach Postgres"
}

variable "db_name" {
  type        = string
  description = "Application database name"
}

variable "db_username" {
  type        = string
  description = "Master username for the RDS instance"
}

variable "ml_inference_security_group_id" {
  type        = string
  description = "ML Inference's ECS tasks security group ID, allowed to reach the broker"
}

variable "alerting_security_group_id" {
  type        = string
  description = "Alerting's ECS tasks security group ID, allowed to reach the broker"
}