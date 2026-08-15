terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "rtrp-terraform-state-04b6152c"
    key            = "cache/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "vpc/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "terraform_remote_state" "ecs" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "ecs/terraform.tfstate"
    region = "eu-north-1"
  }
}

module "cache" {
  source = "../modules/cache"

  project_name       = var.project_name
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  engine_version     = var.engine_version

  ecs_tasks_security_group_id   = data.terraform_remote_state.ecs.outputs.ecs_tasks_security_group_id
  risk_engine_security_group_id = data.terraform_remote_state.ecs.outputs.risk_engine_security_group_id
}