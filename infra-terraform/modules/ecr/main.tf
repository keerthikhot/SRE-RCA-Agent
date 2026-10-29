###############################################################################
# ECR Module
#
# Creates one ECR repository per service listed in `repositories`.
# Default repos:
#   • ai-sre-agent   – the main FastAPI SRE agent
#
# Features:
#   • Image scanning on push
#   • AES256 encryption
#   • Lifecycle policy – keep only the last 30 tagged images, expire untagged
#   • Cross-account pull policy (optional)
###############################################################################

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE" # set IMMUTABLE for strict prod (SHA-pinned)

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.project}/${each.value}"
  })
}

###############################################################################
# Lifecycle Policy
# – Keep 30 most-recent tagged images; expire untagged after 1 day
###############################################################################

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 30 tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v", "sha-", "latest"]
          countType     = "imageCountMoreThan"
          countNumber   = 30
        }
        action = { type = "expire" }
      }
    ]
  })
}

###############################################################################
# Repository Policy – allow pull from EC2 instance profile
###############################################################################

data "aws_caller_identity" "current" {}

resource "aws_ecr_repository_policy" "pull_from_node" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowNodePull"
        Effect = "Allow"
        Principal = {
          AWS = var.k3s_node_role_arn
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      },
      {
        Sid    = "AllowGHActionsPush"
        Effect = "Allow"
        Principal = {
          AWS = var.github_actions_role_arn != "" ? var.github_actions_role_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
      }
    ]
  })
}
