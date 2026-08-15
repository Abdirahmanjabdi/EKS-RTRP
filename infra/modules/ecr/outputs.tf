output "repository_url" {
  value       = aws_ecr_repository.trade_api.repository_url
  description = "The URL of the ECR repository for pushing/pulling images"
}

output "risk_engine_repository_url" {
  value       = aws_ecr_repository.risk_engine.repository_url
  description = "The URL of the ECR repository for the Risk Engine image"
}
