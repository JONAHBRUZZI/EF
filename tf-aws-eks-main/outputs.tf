output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Endpoint for the Kubernetes API server."
  value       = aws_eks_cluster.this.endpoint
}


output "fargate_profile_name" {
  description = "Name of the EKS Fargate profile (only when node_or_fargate = fargate)."
  value       = var.node_or_fargate == "fargate" ? aws_eks_fargate_profile.this[0].fargate_profile_name : null
}

output "configure_kubectl_command" {
  description = "Command to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.this.name}"
}

output "ecr_repository_urls" {
  description = "Map of service name to ECR repository URL."
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "frontend_lb_security_group_id" {
  description = "Security Group a asignar al Load Balancer del Service frontend (aws-load-balancer-security-groups)."
  value       = aws_security_group.frontend_lb.id
}

output "node_security_group_id" {
  description = "Security Group restrictivo de las instancias del node group."
  value       = var.node_or_fargate == "nodes" ? aws_security_group.node_group[0].id : null
}

output "cluster_additional_security_group_id" {
  description = "Security Group adicional del plano de control EKS."
  value       = aws_security_group.cluster_additional.id
}

output "frontend_node_port" {
  description = "NodePort fijo usado por el Service frontend, para referencia en el manifiesto de k8s."
  value       = var.frontend_node_port
}
