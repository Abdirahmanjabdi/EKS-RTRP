output "endpoint" {
  value       = module.database.endpoint
  description = "PostgreSQL connection endpoint"
}

output "db_name" {
  value       = module.database.db_name
}

output "credentials_secret_arn" {
  value       = module.database.credentials_secret_arn
}

output "security_group_id" {
  value       = module.database.security_group_id
}