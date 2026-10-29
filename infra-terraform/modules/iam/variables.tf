variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "ses_sender_email" {
  description = "Verified SES sender email address for the SES inline policy condition"
  type        = string
  default     = "alerts@example.com"
}

variable "create_github_oidc_role" {
  description = "Set to true to create the GitHub Actions OIDC role (requires github_repo)"
  type        = bool
  default     = true
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider resource in IAM (set to false if already created in AWS account)"
  type        = bool
  default     = true
}

variable "github_repo" {
  description = "GitHub repository in the format owner/repo (e.g. acme/ai-sre-agent)"
  type        = string
  default     = "your-github-org/ai-sre-agent"
}

variable "ecr_repository_arns" {
  description = "List of ECR repository ARNs that GitHub Actions can push to"
  type        = list(string)
  default     = []
}

variable "tfstate_bucket" {
  description = "Name of the S3 bucket holding Terraform state (for GitHub Actions role)"
  type        = string
  default     = ""
}

variable "tflock_table" {
  description = "Name of the DynamoDB table used for state locking"
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
