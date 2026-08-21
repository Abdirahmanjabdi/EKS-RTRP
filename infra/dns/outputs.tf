output "name_servers" {
  value       = module.dns.name_servers
  description = "The 4 AWS Route 53 nameservers that must be registered in Cloudflare"
}

output "certificate_arn" {
  value       = module.dns.certificate_arn
  description = "The ARN of the validated ACM TLS certificate"
}