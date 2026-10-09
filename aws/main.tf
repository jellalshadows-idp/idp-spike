terraform {
  required_version = "1.12.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
  }
}

variable "env" {
  type = string
}

variable "image_tag_mutability" {
  type = string
}

# Credentials come from AWS_ACCESS_KEY_ID (= the 12-digit account id) and
# AWS_SECRET_ACCESS_KEY. Endpoints and skip flags come from floci_override.tf.json,
# written by CI (spec §5.6), so this file stays emulator-agnostic.
provider "aws" {
  region = "eu-west-1"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_ecr_repository" "api" {
  name                 = "api"
  image_tag_mutability = var.image_tag_mutability
}

resource "aws_iam_role" "ci" {
  name = "api-${var.env}-ci"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:jellalshadows-idp/api:environment:${var.env}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "push" {
  name = "ecr-push"
  role = aws_iam_role.ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      {
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart"]
        Resource = aws_ecr_repository.api.arn
      }
    ]
  })
}

output "role_arn" {
  value = aws_iam_role.ci.arn
}

output "repository_url" {
  value = aws_ecr_repository.api.repository_url
}
