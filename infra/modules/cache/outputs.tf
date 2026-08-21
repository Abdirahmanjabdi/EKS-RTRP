output "primary_endpoint" {
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
  description = "Valkey primary endpoint (host)"
}

output "port" {
  value       = 6379
  description = "Valkey port"
}

output "auth_token_secret_arn" {
  value       = aws_secretsmanager_secret.redis_auth.arn
  description = "Secrets Manager ARN holding the Valkey AUTH token"
}

output "security_group_id" {
  value       = aws_security_group.redis.id
  description = "Security group ID for the cache"
}