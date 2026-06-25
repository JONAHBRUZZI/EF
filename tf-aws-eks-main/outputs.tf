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
