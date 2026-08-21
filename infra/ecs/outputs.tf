output "alb_dns_name" {
  value       = module.ecs.alb_dns_name
  description = "Public DNS name of the ALB serving the Trade API"
}

output "alb_hosted_zone_id" {
  description = "The canonical hosted zone ID of the Application Load Balancer"
  value       = module.ecs.alb_hosted_zone_id
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID of the ECS tasks, for peer ingress rules from other modules"
  value       = module.ecs.ecs_tasks_security_group_id
}

output "risk_engine_security_group_id" {
  description = "Security group ID of the Risk Engine tasks, for peer ingress rules from other modules"
  value       = module.ecs.risk_engine_security_group_id
}

output "ml_inference_security_group_id" {
  description = "Security group ID of the ML Inference tasks, for peer ingress rules from other modules"
  value       = module.ecs.ml_inference_security_group_id
}

output "alerting_security_group_id" {
  description = "Security group ID of the Alerting tasks, for peer ingress rules from other modules"
  value       = module.ecs.alerting_security_group_id
}