# 1. Create Route 53 Hosted Zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# 2. Request ACM Certificate for Subdomain
resource "aws_acm_certificate" "cert" {
  domain_name       = var.subdomain_name
  validation_method = "DNS"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 3. Automatically create DNS validation records in Route 53
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# 4. Wait for ACM to confirm validation via DNS
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 5. Route 53 Alias Record pointing Subdomain to our ALB
resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.subdomain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_hosted_zone_id
    evaluate_target_health = true
  }
}
