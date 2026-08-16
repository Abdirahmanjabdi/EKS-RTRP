output "repository_url" {
  value       = module.ecr.repository_url
  description = "The URL of the ECR repository for pushing/pulling images"
}

output "risk_engine_repository_url" {
  value       = module.ecr.risk_engine_repository_url
  description = "The URL of the ECR repository for the Risk Engine image"
}

