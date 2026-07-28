variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "AWS region for the VPC infrastructure"
}

variable "project_name" {
  type        = string
  default     = "rtrp"
  description = "Project name prefix"
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Base CIDR block for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  description = "CIDR blocks for public subnets (spans 2 AZs)"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
  description = "CIDR blocks for private subnets (spans 2 AZs)"
}