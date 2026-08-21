output "topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "SNS topic ARN for alert notifications"
}
