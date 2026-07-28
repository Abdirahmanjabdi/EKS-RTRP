output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "Public DNS name of the ALB serving the Trade API"
}