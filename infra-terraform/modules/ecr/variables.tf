variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "repositories" {
  description = "List of repository names to create (project/ prefix is prepended automatically)"
  type        = list(string)
  default     = ["ai-sre-agent"]
}

variable "k3s_node_role_arn" {
  description = "ARN of the k3s node IAM role (granted pull access)"
  type        = string
}

variable "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (granted push access). Empty string = skip."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
