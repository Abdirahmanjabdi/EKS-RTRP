variable "domain_name" {
  type        = string
  description = "Root apex domain"
}

variable "subdomain_name" {
  type        = string
  description = "The application subdomain for the Trade API"
}

variable "alb_dns_name" {
  type        = string
  description = "DNS name of the ALB to alias the subdomain to"
}

variable "alb_hosted_zone_id" {
  type        = string
  description = "Canonical hosted zone ID of the ALB"
}
