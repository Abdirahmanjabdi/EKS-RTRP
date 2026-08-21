variable "aws_region" {
  type    = string
  default = "eu-north-1"
}

variable "project_name" {
  type    = string
  default = "rtrp"
}

variable "domain_name" {
  type    = string
  default = "sentineltrading.org"
  description = "Root apex domain"
}

variable "subdomain_name" {
  type    = string
  default = "tm.sentineltrading.org"
  description = "The application subdomain for the Trade API"
}