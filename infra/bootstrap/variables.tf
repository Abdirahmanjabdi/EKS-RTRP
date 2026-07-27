variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "AWS region for the bootstrap state backend infrastructure"
}

variable "project_name" {
  type        = string
  default     = "rtrp"
  description = "Project name prefix for global resource identification"
}

variable "environment" {
  type        = string
  default     = "shared"
  description = "Environment tag (e.g., shared, prod)"
}