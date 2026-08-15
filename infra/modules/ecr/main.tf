resource "aws_ecr_repository" "trade_api" {
  name                 = "${var.project_name}-${var.repository_name}"
  image_tag_mutability = "IMMUTABLE" # Enforces absolute artifact traceability

  image_scanning_configuration {
    scan_on_push = true # Automated free CVE security checks
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecr_repository" "risk_engine" {
  name                 = "${var.project_name}-risk-engine"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ecr_repository" "prometheus" {
  name                 = "${var.project_name}-prometheus"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
