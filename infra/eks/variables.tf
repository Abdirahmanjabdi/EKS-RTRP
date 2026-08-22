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

variable "cluster_version" {
    type        = string
    default     = "1.31"
    description = "EKS cluster version"
}

