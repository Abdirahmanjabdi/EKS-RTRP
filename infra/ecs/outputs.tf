output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "Public DNS name of the ALB serving the Trade API"
}

output "alb_hosted_zone_id" {
  description = "The canonical hosted zone ID of the Application Load Balancer"
  value       = aws_lb.main.zone_id
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID of the ECS tasks, for peer ingress rules from other modules"
  value       = aws_security_group.ecs_tasks.id
}