output "broker_id" {
  value       = module.messaging.broker_id
  description = "Amazon MQ broker ID"
}

output "amqps_endpoint" {
  value       = module.messaging.amqps_endpoint
  description = "AMQPS endpoint URL for the RabbitMQ broker (not the HTTPS management console URL)"
}

output "credentials_secret_arn" {
  value       = module.messaging.credentials_secret_arn
  description = "Secrets Manager ARN holding the broker username/password"
}
