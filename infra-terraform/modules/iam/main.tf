###############################################################################
# IAM Module
#
# Creates:
#   • k3s_node_role       – EC2 instance profile for the k3s server
#   • github_actions_role – OIDC role for GitHub Actions CI/CD pipeline
#   • ses_send_policy     – allows SES:SendRawEmail (attached to node role)
#
# The node role grants:
#   • ECR pull (AmazonEC2ContainerRegistryReadOnly)
#   • SES SendRawEmail (custom inline policy)
#   • SSM core (AmazonSSMManagedInstanceCore – replaces SSH in production)
#   • CloudWatch agent (CloudWatchAgentServerPolicy)
###############################################################################

###############################################################################
# k3s Node IAM Role
###############################################################################

resource "aws_iam_role" "k3s_node" {
  name = "${var.project}-${var.environment}-k3s-node-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-k3s-node-role"
  })
}

###############################################################################
# Managed Policy Attachments
###############################################################################

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.k3s_node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

###############################################################################
# Inline Policy - SSM PutParameter (for kubeconfig upload)
###############################################################################

resource "aws_iam_role_policy" "ssm_kubeconfig_put" {
  name = "ssm-kubeconfig-put"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowKubeconfigPut"
      Effect = "Allow"
      Action = [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters"
      ]
      Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"
    }]
  })
}

###############################################################################
# Inline Policy – SES SendRawEmail
###############################################################################

resource "aws_iam_role_policy" "ses_send" {
  name = "ses-send-raw-email"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowSESSendRaw"
      Effect = "Allow"
      Action = [
        "ses:SendEmail",
        "ses:SendRawEmail"
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "ses:FromAddress" = var.ses_sender_email
        }
      }
    }]
  })
}

###############################################################################
# Inline Policy – Secrets Manager (Anthropic / API keys)
###############################################################################

resource "aws_iam_role_policy" "secrets_read" {
  name = "secrets-manager-read"
  role = aws_iam_role.k3s_node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadAgentSecrets"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/*"
    }]
  })
}

data "aws_caller_identity" "current" {}

###############################################################################
# EC2 Instance Profile  (wraps the role so EC2 can use it)
###############################################################################

resource "aws_iam_instance_profile" "k3s_node" {
  name = "${var.project}-${var.environment}-k3s-node-profile"
  role = aws_iam_role.k3s_node.name

  tags = var.tags
}

###############################################################################
# GitHub Actions OIDC Role
# Allows GitHub Actions CI/CD to push images to ECR and deploy
###############################################################################

resource "aws_iam_openid_connect_provider" "github" {
  count           = var.create_github_oidc_role && var.create_github_oidc_provider ? 1 : 0
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c5876bdab70c7927b66a479e4622c463f4b77f1"]

  tags = var.tags
}

locals {
  github_oidc_arn = var.create_github_oidc_role ? (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  ) : ""
}

resource "aws_iam_role" "github_actions" {
  count = var.create_github_oidc_role ? 1 : 0
  name  = "${var.project}-${var.environment}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.github_oidc_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-github-actions-role"
  })
}

resource "aws_iam_role_policy" "github_actions_ecr" {
  count = var.create_github_oidc_role ? 1 : 0
  name  = "ecr-push-and-deploy"
  role  = aws_iam_role.github_actions[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPushPull"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${var.project}/*"]
      },
      {
        Sid    = "S3TerraformState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.tfstate_bucket}",
          "arn:aws:s3:::${var.tfstate_bucket}/*"
        ]
      },
      {
        Sid      = "DynamoLock"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:DeleteItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.tflock_table}"
      }
    ]
  })
}
