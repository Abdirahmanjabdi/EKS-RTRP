output "broker_id" {
  value       = aws_mq_broker.rabbitmq.id
  description = "Amazon MQ broker ID"
}

output "amqps_endpoints" {
  value       = aws_mq_broker.rabbitmq.instances[0].endpoints
  description = "AMQPS endpoint URLs for the RabbitMQ broker"
}

output "credentials_secret_arn" {
  value       = aws_secretsmanager_secret.rabbitmq.arn
  description = "Secrets Manager ARN holding the broker username/password"
}
