output "k3s_node_role_arn" {
  description = "ARN of the k3s node IAM role"
  value       = aws_iam_role.k3s_node.arn
}

output "k3s_node_role_name" {
  description = "Name of the k3s node IAM role"
  value       = aws_iam_role.k3s_node.name
}

output "k3s_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.k3s_node.name
}

output "k3s_instance_profile_arn" {
  description = "EC2 instance profile ARN"
  value       = aws_iam_instance_profile.k3s_node.arn
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions OIDC role (empty if not created)"
  value       = var.create_github_oidc_role ? aws_iam_role.github_actions[0].arn : ""
}
