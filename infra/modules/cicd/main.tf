# 1. GitHub OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 2. IAM Role for GitHub Actions (Allows main or feature branch testing safely via wildcard)
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
            # ADD BOTH CONDITIONS HERE AS A LIST:
            "token.actions.githubusercontent.com:sub" = [
              "repo:Abdirahmanjabdi/RTRP:ref:refs/heads/*",
              "repo:Abdirahmanjabdi/RTRP:environment:production-infra"
            ]
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
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = ["arn:aws:s3:::rtrp-terraform-state-04b6152c"]
        Condition = {
          StringLike = {
            "s3:prefix" = ["ecs/*", "ecs"]
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:HeadObject",
          "ecs:*",
          "elasticloadbalancing:*",
          "ec2:*",
          "iam:*",
          "logs:*"
        ]
        Resource = ["arn:aws:s3:::rtrp-terraform-state-04b6152c/ecs/*"]
      }
    ]
  })
}

# 4. Comprehensive Least-Privilege & Infrastructure Policy
resource "aws_iam_role_policy" "ci_permissions" {
  name = "rtrp-ci-permissions"
  role = aws_iam_role.github_ci.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },

      {
        Effect   = "Allow"
        Action   = ["ecr:CreateRepository", "ecr:TagResource", "ecr:UntagResource"]
        Resource = "*"
      },

      {
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },

      {
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticache:*"]
        Resource = "*"
      },

      {
        Effect = "Allow"
        Action = ["elasticache:*"]
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
        Resource = [
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-trade-api",
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-risk-engine",
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-prometheus"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:*",
          "elasticloadbalancing:*",
          "ec2:*",
          "iam:*",
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:eu-north-1:026703081738:table/rtrp-terraform-locks"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::rtrp-terraform-state-04b6152c",
          "arn:aws:s3:::rtrp-terraform-state-04b6152c/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:GetRepositoryPolicy",
          "ecr:ListTagsForResource"
        ]
        Resource = [
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-trade-api",
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-risk-engine",
          "arn:aws:ecr:eu-north-1:026703081738:repository/rtrp-prometheus"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "route53:GetHostedZone",
          "route53:ListResourceRecordSets",
          "route53:ChangeResourceRecordSets",
          "route53:ListTagsForResource",
          "route53:GetChange"
        ]
        Resource = [
          "arn:aws:route53:::hostedzone/*",
          "arn:aws:route53:::change/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListTagsForCertificate",
          "acm:RequestCertificate",
          "acm:AddTagsToCertificate"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["mq:*"]
        Resource = "*"
      },

     {
        Effect   = "Allow"
        Action   = ["servicediscovery:*"]
        Resource = "*"
      },

      { Effect   = "Allow"
        Action   = ["secretsmanager:CreateSecret"]
        Resource = "*"
      }, #policy for secrets manager to create secret
      { Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:TagResource",
          "secretsmanager:UntagResource",
          "secretsmanager:GetResourcePolicy"
        ]
        Resource = "arn:aws:secretsmanager:eu-north-1:026703081738:secret:rtrp-*"
      }

    ]
  })
}
