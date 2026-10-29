###############################################################################
# environments/prod/outputs.tf
###############################################################################

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "k3s_public_ip" {
  description = "Elastic IP of the k3s server – set this as the API server in your kubeconfig"
  value       = module.k3s.public_ip
}

output "k3s_instance_id" {
  description = "EC2 instance ID of the k3s server"
  value       = module.k3s.instance_id
}

output "fetch_kubeconfig_command" {
  description = "Run this locally after apply to download the kubeconfig"
  value       = module.k3s.fetch_kubeconfig_command
}

output "kubeconfig_ssm_param" {
  description = "SSM parameter path for the kubeconfig"
  value       = module.k3s.kubeconfig_ssm_param
}

output "ecr_repository_urls" {
  description = "ECR repository URLs (use these in your CI pipeline)"
  value       = module.ecr.repository_urls
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC – add to your GitHub secrets"
  value       = module.iam.github_actions_role_arn
}

output "k3s_node_role_arn" {
  description = "k3s node IAM role ARN"
  value       = module.iam.k3s_node_role_arn
}

output "k3s_server_sg_id" {
  description = "Security group ID for the k3s server"
  value       = module.security_groups.k3s_server_sg_id
}
