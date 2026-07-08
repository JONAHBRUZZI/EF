variable "environment" {
  description = "Environment name used to build resource names and tags."
  type        = string
}

variable "project_name" {
  description = "Project name used to build resource names and tags."
  type        = string
}

variable "owner_name" {
  description = "Owner name applied to resources through default provider tags."
  type        = string
}

variable "aws_region" {
  description = "AWS region where the EKS cluster and related resources are created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.35"
}

variable "node_or_fargate" {
  description = "Compute type: 'nodes' for EC2 Managed Node Group, 'fargate' for Fargate profiles."
  type        = string
  default     = "fargate"

  validation {
    condition     = contains(["nodes", "fargate"], var.node_or_fargate)
    error_message = "Must be either 'nodes' or 'fargate'."
  }
}

variable "aws_profile" {
  description = "AWS CLI profile used by the provider. Leave empty for CI/CD (uses env credentials)."
  type        = string
}

variable "fargate_profile_selectors" {
  description = "Fargate profile selectors that decide which Kubernetes pods run on Fargate."
  type = list(object({
    namespace = string
    labels    = optional(map(string), {})
  }))
  default = [
    {
      namespace = "default"
      labels    = {}
    },
    {
      namespace = "kube-system"
      labels = {
        k8s-app = "kube-dns"
      }
    },
    {
      namespace = "tienda"
      labels    = {}
    }
  ]
}

variable "apps_repository" {
  description = "Git repository URL for application manifests."
  type        = list(string)
  default     = []
}

variable "node_group_instance_types" {
  description = "List of instance types for the managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_group_capacity_type" {
  description = "Capacity type for node groups: 'ON_DEMAND' or 'SPOT'."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_group_capacity_type)
    error_message = "Must be either 'ON_DEMAND' or 'SPOT'."
  }
}

variable "frontend_node_port" {
  description = "NodePort fijo usado por el Service frontend (type=LoadBalancer). Se referencia en el Security Group del LB y de los nodos para restringir el trafico a un unico puerto conocido."
  type        = number
  default     = 30080
}

variable "enable_node_cloudwatch_metrics" {
  description = "Adjunta CloudWatchAgentServerPolicy al rol del node group para habilitar metricas/logs reales en CloudWatch Container Insights. Deshabilitado por defecto porque varios Learner Labs bloquean iam:AttachRolePolicy incluso sobre roles pre-existentes; dejarlo en false garantiza que Terraform nunca falle por permisos de IAM."
  type        = bool
  default     = false
}