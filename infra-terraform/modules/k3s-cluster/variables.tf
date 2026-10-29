variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "public_subnet_id" {
  description = "Subnet ID where the k3s EC2 instance is placed"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the k3s instance"
  type        = string
}

variable "instance_profile_name" {
  description = "EC2 instance profile name (from the IAM module)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the k3s server"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "k3s_version" {
  description = "k3s version to install (e.g. v1.30.2+k3s1). Empty = latest."
  type        = string
  default     = ""
}

variable "public_key_material" {
  description = "SSH public key material. Leave empty to skip key pair creation."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
