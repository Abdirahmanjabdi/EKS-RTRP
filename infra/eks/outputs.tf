output "cluster_name" {
    value       = module.eks.cluster_name
    description = "EKS cluster name"
}

output "cluster_endpoint" {
    value       = module.eks.cluster_endpoint
    description = "EKS cluster endpoint"
}

output "cluster_certificate_authority" {
    value       = module.eks.cluster_certificate_authority
    description = "EKS cluster certificate authority data"
    sensitive   = true
}

output "oidc_provider_url" {
    value       = module.eks.oidc_provider_url
    description = "EKS cluster OIDC provider URL"
}

output "oidc_provider_arn" {
    value       = module.eks.oidc_provider_arn
    description = "EKS cluster OIDC provider ARN"
}

output "external_dns_role_arn" {
  value = module.eks.external_dns_role_arn
}

output "cert_manager_role_arn" {
  value = module.eks.cert_manager_role_arn
}