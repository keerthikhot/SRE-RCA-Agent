output "k3s_server_sg_id" {
  description = "Security group ID for the k3s server / node"
  value       = aws_security_group.k3s_server.id
}

output "alb_sg_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}
