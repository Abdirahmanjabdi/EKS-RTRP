variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "AWS region for ECR"
}

variable "project_name" {
  type        = string
  default     = "rtrp"
  description = "Project name prefix"
}

variable "repository_name" {
  type        = string
  default     = "trade-api"
  description = "Name of the ECR repository"
}