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
        key            = "eks/terraform.tfstate"
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



module "eks" {
  source = "../modules/eks"
  project_name       = var.project_name
  aws_region         = var.aws_region
  cluster_name       = "${var.project_name}-eks"
  cluster_version    = var.cluster_version
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
}