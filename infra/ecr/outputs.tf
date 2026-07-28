output "repository_url" {
  value       = aws_ecr_repository.trade_api.repository_url
  description = "The URL of the ECR repository for pushing/pulling images"
}