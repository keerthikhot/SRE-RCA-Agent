output "repository_urls" {
  description = "Map of repository name → ECR URL"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository name → ECR ARN"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}

output "repository_arns_list" {
  description = "Flat list of ECR repository ARNs (convenient for IAM policies)"
  value       = [for v in aws_ecr_repository.this : v.arn]
}

output "registry_id" {
  description = "ECR registry ID (= AWS account ID)"
  value       = length(aws_ecr_repository.this) > 0 ? values(aws_ecr_repository.this)[0].registry_id : ""
}
