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
    key            = "dns/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "ecs" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "ecs/terraform.tfstate"
    region = "eu-north-1"
  }
}

module "dns" {
  source = "../modules/dns"

  domain_name        = var.domain_name
  subdomain_name     = var.subdomain_name
  alb_dns_name       = data.terraform_remote_state.ecs.outputs.alb_dns_name
  alb_hosted_zone_id = data.terraform_remote_state.ecs.outputs.alb_hosted_zone_id
}