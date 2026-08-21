resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "rtrp.local"
  description = "Internal service discovery for RTRP services"
  vpc         = var.vpc_id
}

resource "aws_service_discovery_service" "trade_api" {
  name = "trade-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}

resource "aws_service_discovery_service" "risk_engine" {
  name = "risk-engine"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }
}