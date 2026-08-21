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
    key            = "cicd/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "rtrp-terraform-locks"
  }
}

provider "aws" {
  region = "eu-north-1"
}

module "cicd" {
  source = "../modules/cicd"
}