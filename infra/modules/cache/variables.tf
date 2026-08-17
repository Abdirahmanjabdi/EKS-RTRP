variable "project_name" {
  type        = string
  description = "Project name prefix"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to deploy the cache subnet group and security group into"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the cache subnet group"
}

variable "ecs_tasks_security_group_id" {
  type        = string
  description = "Trade API's ECS tasks security group ID, allowed to reach the cache"
}

variable "risk_engine_security_group_id" {
  type        = string
  description = "Risk Engine's ECS tasks security group ID, allowed to reach the cache"
}

variable "engine_version" {
  type        = string
  default     = "9.1"
  description = "Valkey engine version - verified via aws elasticache describe-cache-engine-versions on 2026-08-15"
}

variable "ml_inference_security_group_id" {
  type        = string
  description = "ML Inference's ECS tasks security group ID, allowed to reach the broker"
}