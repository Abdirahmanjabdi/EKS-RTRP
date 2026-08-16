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

data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "messaging/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "database/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "terraform_remote_state" "cache" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "cache/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "terraform_remote_state" "alerting" {
  backend = "s3"
  config = {
    bucket = "rtrp-terraform-state-04b6152c"
    key    = "alerting/terraform.tfstate"
    region = "eu-north-1"
  }
}

module "ecs" {
  source = "../modules/ecs"

  aws_region          = var.aws_region
  project_name        = var.project_name
  vpc_id              = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_ids   = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids  = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  rabbitmq_amqps_endpoint         = data.terraform_remote_state.messaging.outputs.amqps_endpoint
  rabbitmq_credentials_secret_arn = data.terraform_remote_state.messaging.outputs.credentials_secret_arn

  postgres_host                   = split(":", data.terraform_remote_state.database.outputs.endpoint)[0]
  postgres_port                   = split(":", data.terraform_remote_state.database.outputs.endpoint)[1]
  postgres_db                     = data.terraform_remote_state.database.outputs.db_name
  postgres_credentials_secret_arn = data.terraform_remote_state.database.outputs.credentials_secret_arn

  redis_host                  = data.terraform_remote_state.cache.outputs.primary_endpoint
  redis_port                  = data.terraform_remote_state.cache.outputs.port
  redis_auth_token_secret_arn = data.terraform_remote_state.cache.outputs.auth_token_secret_arn

  sns_topic_arn = data.terraform_remote_state.alerting.outputs.topic_arn
}