variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "AWS region for the messaging infrastructure"
}

variable "project_name" {
  type        = string
  default     = "rtrp"
  description = "Project name prefix"
}

variable "rabbitmq_username" {
  type        = string
  default     = "rtrpadmin"
  description = "Administrative username for the RabbitMQ broker"
}
