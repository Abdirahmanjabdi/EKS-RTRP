output "cluster_name" {
    value       = aws_eks_cluster.main.name
    description = "EKS cluster name"
}

output "cluster_endpoint" {
    value       = aws_eks_cluster.main.endpoint
    description = "EKS cluster endpoint"
}

output "cluster_certificate_authority" {
    value       = aws_eks_cluster.main.certificate_authority[0].data
    description = "EKS cluster certificate authority data"
    sensitive   = true
}

output "cluster_security_group_id" {
    value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    description = "EKS cluster security group ID"
}

output "oidc_provider_url" {
    value       = aws_iam_openid_connect_provider.eks.url
    description = "EKS cluster OIDC provider URL"
}

output "oidc_provider_arn" {
    value       = aws_iam_openid_connect_provider.eks.arn
    description = "EKS cluster OIDC provider ARN"
}

output "node_role_arn" {
    value       = aws_iam_role.nodes.arn
    description = "EKS worker node IAM role ARN"
}

output "external_dns_role_arn" {
  value       = aws_iam_role.external_dns.arn
  description = "IAM role ARN for ExternalDNS IRSA"
}

output "cert_manager_role_arn" {
  value       = aws_iam_role.cert_manager.arn
  description = "IAM role ARN for CertManager IRSA"
}