variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "project_name" {
  type    = string
  default = "rtrp"
}

variable "engine_version" {
  type        = string
  default     = "9.1"
  description = "Valkey engine version - verified via aws elasticache describe-cache-engine-versions on 2026-08-15"
}