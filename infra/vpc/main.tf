terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # --- REMOTE BACKEND WIRING ---
  # Replace with the exact bucket and table names output from infra/bootstrap
  backend "s3" {
    bucket         = "rtrp-terraform-state-04b6152c"
    key            = "vpc/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source = "../modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}