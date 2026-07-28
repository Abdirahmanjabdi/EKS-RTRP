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
    key            = "ecs/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-north-1"
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "vpc/terraform.tfstate"
    region = "eu-north-1"
  }
}