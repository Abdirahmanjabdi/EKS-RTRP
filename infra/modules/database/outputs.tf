output "endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "PostgreSQL connection endpoint (host:port)"
}

output "db_name" {
  value       = aws_db_instance.main.db_name
  description = "Database name"
}

output "credentials_secret_arn" {
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
  description = "Secrets Manager ARN holding the RDS master username/password (AWS-managed)"
}

output "security_group_id" {
  value       = aws_security_group.postgres.id
  description = "Security group ID for the PostgreSQL instance"
}