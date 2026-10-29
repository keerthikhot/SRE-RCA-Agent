variable "project" {
  description = "Short project name prefix"
  type        = string
}

variable "environment" {
  description = "Environment label"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR of the VPC (used for intra-cluster rule)"
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed SSH / management access to the k3s node"
  type        = list(string)
  default     = ["0.0.0.0/0"] # override in production!
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
