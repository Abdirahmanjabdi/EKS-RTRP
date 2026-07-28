terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "rtrp-terraform-state-04b6152c"
    key            = "ecr/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

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