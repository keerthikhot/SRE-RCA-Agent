output "instance_id" {
  description = "EC2 instance ID of the k3s server"
  value       = aws_instance.k3s.id
}

output "public_ip" {
  description = "Elastic IP address attached to the k3s server"
  value       = aws_eip.k3s.public_ip
}

output "private_ip" {
  description = "Private IP of the k3s EC2 instance"
  value       = aws_instance.k3s.private_ip
}

output "kubeconfig_ssm_param" {
  description = "SSM parameter path where the kubeconfig is stored"
  value       = "/${var.project}/${var.environment}/k3s/kubeconfig"
}

output "fetch_kubeconfig_command" {
  description = "CLI command to download the kubeconfig locally after apply"
  value       = "aws ssm get-parameter --name /${var.project}/${var.environment}/k3s/kubeconfig --with-decryption --query Parameter.Value --output text > ~/.kube/${var.project}-${var.environment}.yaml"
}

output "cw_log_group" {
  description = "CloudWatch log group for k3s logs"
  value       = aws_cloudwatch_log_group.k3s.name
}
