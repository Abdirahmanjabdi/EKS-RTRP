output "name_servers" {
  value       = aws_route53_zone.main.name_servers
  description = "The 4 AWS Route 53 nameservers that must be registered in Cloudflare"
}

output "certificate_arn" {
  value       = aws_acm_certificate.cert.arn
  description = "The ARN of the validated ACM TLS certificate"
}