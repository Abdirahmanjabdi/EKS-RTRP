variable "project_name" {
    type        = string
    description = "Project name prefix"
}

variable "aws_region" {
    type        = string
    description = "AWS region"
}

variable "cluster_name" {
    type        = string
    description = "EKS cluster name for subnet discovery tags"
}

variable "cluster_version" {
    type        = string
    description = "EKS cluster version"
    default     = "1.31"
}

variable "vpc_id" {
    type        = string
    description = "VPC ID to deploy the EKS cluster into"
}

variable "private_subnet_ids" {
    type        = list(string)
    description = "Private subnet IDs for the EKS cluster"
}

variable "public_subnet_ids" {
    type        = list(string)
    description = "Public subnet IDs for the EKS cluster"
}

variable "node_instance_type" {
    type        = string
    description = "EC2 instance type for EKS worker nodes"
    default     = "t3.small"
}

variable "node_desired_size" {
    type        = number
    description = "Desired number of EKS worker nodes"  
    default     = 3
}

variable "node_min_size" {
    type        = number
    description = "Minimum number of EKS worker nodes"
    default     = 2
}

variable "node_max_size" {
    type        = number
    description = "Maximum number of EKS worker nodes"
    default     = 4
}


