output "repository_url" {
  value       = aws_ecr_repository.trade_api.repository_url
  description = "The URL of the ECR repository for pushing/pulling images"
}

output "risk_engine_repository_url" {
  value       = aws_ecr_repository.risk_engine.repository_url
  description = "The URL of the ECR repository for the Risk Engine image"
}

output "prometheus_repository_url" {
  value       = aws_ecr_repository.prometheus.repository_url
  description = "The URL of the ECR repository for the Prometheus image"
}

output "grafana_repository_url" {
  value       = aws_ecr_repository.grafana.repository_url
  description = "The URL of the ECR repository for the Grafana image"
}