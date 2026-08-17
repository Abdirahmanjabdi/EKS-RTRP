output "broker_id" {
  value       = aws_mq_broker.rabbitmq.id
  description = "Amazon MQ broker ID"
}

output "amqps_endpoint" {
  # endpoints has both the HTTPS console URL and the amqps:// URL, order not
  # guaranteed — filter by scheme instead of indexing [0] blindly.
  value       = [for e in aws_mq_broker.rabbitmq.instances[0].endpoints : e if startswith(e, "amqps://")][0]
  description = "AMQPS endpoint URL for the RabbitMQ broker (not the HTTPS management console URL)"
}

output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.rabbitmq.arn
  description = "Secrets Manager ARN holding the broker username/password"
}

