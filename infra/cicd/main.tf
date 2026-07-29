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

# 1. GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # Standard GitHub Actions OIDC thumbprint
}

# 2. IAM Role for GitHub Actions (This was missing!)
resource "aws_iam_role" "github_ci" {
  name = "rtrp-github-ci-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:Abdirahmanjabdi/RTRP:ref:refs/heads/*"
          }
        }
      }
    ]
  })
}

# 3. S3 State Policy
resource "aws_iam_role_policy" "ci_s3_state" {
  name = "rtrp-ci-terraform-s3-state"
  role = aws_iam_role.github_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::rtrp-terraform-state-04b6152c"]
        Condition = {
          StringLike = {
            "s3:prefix" = ["ecs/*", "ecs"]
          }
        }
      },
      {
        Effect = "Allow"
       Effect = "Allow"
        Action = [
          "ecs:*",
          "elasticloadbalancing:*",
          "ec2:*",
          "iam:GetRole",
          "iam:PassRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "logs:*"
        ]
        Resource = ["arn:aws:s3:::rtrp-terraform-state-04b6152c/ecs/*"]
      }
    ]
  })
}


# 4. Least-Privilege Application/ECS/ECR/Infrastructure Policy
resource "aws_iam_role_policy" "ci_permissions" {
  name = "rtrp-ci-permissions"
  role = aws_iam_role.github_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR Access
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-trade-api"
      },
      # ECS & Infrastructure Management Access for Terraform
      {
        Effect = "Allow"
        Action = [
          "ecs:*",
          "elasticloadbalancing:*",
          "ec2:*",
          "iam:GetRole",
          "iam:PassRole",
          "logs:*"
        ]
        Resource = "*"
      },
      # DynamoDB State Locking Access
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:eu-north-1:026703081738:table/rtrp-terraform-locks"
      },
      # S3 Terraform State Access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:HeadObject"
        ]
        Resource = [
          "arn:aws:s3:::rtrp-terraform-state-04b6152c",
          "arn:aws:s3:::rtrp-terraform-state-04b6152c/*"
        ]
      }
    ]
  })
}