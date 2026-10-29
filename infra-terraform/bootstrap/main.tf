###############################################################################
# Bootstrap – Remote State Backend
#
# Run ONCE before any other Terraform:
#   cd terraform/bootstrap
#   terraform init && terraform apply
#
# This creates:
#   • S3 bucket         – stores all .tfstate files
#   • DynamoDB table    – provides state locking (prevents concurrent apply)
###############################################################################

###############################################################################
# Variables
###############################################################################

variable "aws_region" {
  description = "AWS region for all bootstrap resources"
  type        = string
  default     = "ap-south-1"
}

variable "project" {
  description = "Short project name used as a prefix for all resources"
  type        = string
  default     = "ai-sre-agent"
}

variable "environment" {
  description = "Environment label (prod | staging | dev)"
  type        = string
  default     = "prod"
}

###############################################################################
# Random suffix – keeps the S3 bucket name globally unique
###############################################################################

resource "random_id" "suffix" {
  byte_length = 4
}

###############################################################################
# S3 Bucket – Terraform Remote State
###############################################################################

resource "aws_s3_bucket" "tfstate" {
  bucket        = "${var.project}-tfstate-${random_id.suffix.hex}"
  force_destroy = false # safety: never accidentally destroy state

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter { prefix = "" }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

###############################################################################
# DynamoDB Table – State Locking
###############################################################################

resource "aws_dynamodb_table" "tflock" {
  name         = "${var.project}-tflock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform-bootstrap"
  }
}

###############################################################################
# Outputs – copy these into environments/prod/backend.tf
###############################################################################

output "state_bucket_name" {
  description = "S3 bucket name – use as 'bucket' in backend config"
  value       = aws_s3_bucket.tfstate.id
}

output "state_lock_table" {
  description = "DynamoDB table name – use as 'dynamodb_table' in backend config"
  value       = aws_dynamodb_table.tflock.name
}

output "aws_region" {
  description = "Region the bootstrap resources were created in"
  value       = var.aws_region
}
