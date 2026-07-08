data "aws_iam_roles" "all" {}
data "aws_partition" "current" {}

locals {
  name_prefix          = "${var.environment}-${var.project_name}"
  cluster_name         = "${local.name_prefix}-eks"
  fargate_profile_name = "${local.name_prefix}-fargate"
  azs                  = ["us-east-1a", "us-east-1b"] # puede ser dinamico ? 
  cluster_role_name = [
    for role in data.aws_iam_roles.all.names :
    role
    if strcontains(role, "LabEksClusterRole")
  ][0]

  node_role_name = [
    for role in data.aws_iam_roles.all.names :
    role
    if strcontains(role, "LabEksNodeRole")
  ][0]
}

data "aws_iam_role" "cluster" {
  name = local.cluster_role_name
}

data "aws_iam_role" "node" {
  name = local.node_role_name
}

################################################################################
# Observabilidad - CloudWatch Container Insights (opcional, resiliente)
#
# El Learner Lab no permite crear un OIDC Provider (ver comentario del EBS CSI
# Driver mas abajo), por lo que no se puede usar IRSA/Pod Identity para dar
# permisos de CloudWatch al agente. La alternativa clasica (sin IRSA) es usar
# directamente el rol de instancia del node group (LabEksNodeRole) agregandole
# la policy administrada CloudWatchAgentServerPolicy.
#
# Esto se deja detras de una variable (default = false) porque en la mayoria de
# los Learner Labs esta bloqueado modificar/adjuntar policies a los roles
# provistos (iam:AttachRolePolicy suele estar denegado por el propio Lab). Si
# se deja en false (default), Terraform nunca toca IAM y el pipeline no puede
# romperse por este motivo. Si el rol del Lab si lo permite, se puede habilitar
# con TF_VAR_enable_node_cloudwatch_metrics=true sin tocar el resto del codigo.
################################################################################

resource "aws_iam_role_policy_attachment" "node_cloudwatch_agent" {
  count      = var.enable_node_cloudwatch_metrics ? 1 : 0
  role       = data.aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

################################################################################
# VPC 
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = "${local.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 2, i)]
  public_subnets  = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 2, i + length(local.azs))]

  private_subnet_names = [for az in local.azs : "${local.name_prefix}-private-${az}"]
  public_subnet_names  = [for az in local.azs : "${local.name_prefix}-public-${az}"]


  create_igw              = true  # Create Internet Gateway
  enable_nat_gateway      = false # Using custom NAT instance module
  single_nat_gateway      = true  # Group private subnets into one route table
  enable_vpn_gateway      = false # Not using VPN Gateway
  enable_dns_hostnames    = true  # Enable DNS hostnames
  enable_dns_support      = true  # Enable DNS support
  map_public_ip_on_launch = true  # Enable public IP on launch

  public_route_table_tags = {
    Name = "${local.name_prefix}-public-rt"
  }
  private_route_table_tags = {
    Name = "${local.name_prefix}-private-rt"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
    "kubernetes.io/role/elb"                         = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.name_prefix}-eks" = "shared"
    "kubernetes.io/role/internal-elb"                = "1"
  }
}

################################################################################
# NAT Instance for private subnets internet access
################################################################################

module "nat_instance" {
  source = "git::https://github.com/franciscobrioneslavados/terraform-aws-nat-instance.git//.?ref=v1.3.0"

  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnets
  private_subnet_cidrs = module.vpc.private_subnets_cidr_blocks
  route_table_ids      = module.vpc.private_route_table_ids
  project_name         = "${local.name_prefix}-nat"
  environment          = var.environment
  owner_name           = var.owner_name
  instance_type        = "t3.micro"
  ssh_allowed_cidrs    = []
  os_type              = "amazon-linux-2" # or "ubuntu"

  depends_on = [module.vpc]
}

################################################################################
# EKS Cluster
################################################################################

resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${local.cluster_name}/cluster"
  retention_in_days = 7

  tags = {
    Name = "/aws/eks/${local.cluster_name}/cluster"
  }
}

resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = data.aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = module.vpc.public_subnets
    security_group_ids      = [aws_security_group.cluster_additional.id]
  }

  tags = {
    Name = local.cluster_name
  }

  depends_on = [
    aws_cloudwatch_log_group.cluster,
    module.nat_instance,
    aws_security_group_rule.cluster_ingress_https_from_vpc,
    aws_security_group_rule.cluster_egress_to_vpc
  ]

}

################################################################################
# Fargate Pod Execution Role
################################################################################

data "aws_iam_policy_document" "fargate_pod_execution_assume_role" {
  statement {
    sid     = "EKSFargatePodExecutionAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks-fargate-pods.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fargate_pod_execution" {
  count              = var.node_or_fargate == "fargate" ? 1 : 0
  name               = "${local.cluster_name}-pod-execution"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.fargate_pod_execution_assume_role.json

  tags = {
    Name = "${local.cluster_name}-pod-execution"
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  count      = var.node_or_fargate == "fargate" ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution[0].name
}

################################################################################
# Fargate Profile
################################################################################

resource "aws_eks_fargate_profile" "this" {
  count                  = var.node_or_fargate == "fargate" ? 1 : 0
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = local.fargate_profile_name
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution[0].arn
  subnet_ids             = module.vpc.private_subnets

  dynamic "selector" {
    for_each = var.fargate_profile_selectors

    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = {
    Name = local.fargate_profile_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution,
  ]
}

################################################################################
# Launch Template para el Managed Node Group
#
# Se usa un launch template propio unicamente para:
#   1) Adjuntar el Security Group restrictivo aws_security_group.node_group
#   2) Forzar IMDSv2 (http_tokens = "required"), mitigando robo de credenciales
#      via SSRF (endurecimiento basico de las instancias del cluster)
# No se especifica AMI ni user-data: EKS los completa automaticamente con la
# misma imagen y bootstrap que usaria sin launch template.
################################################################################

resource "aws_launch_template" "nodes" {
  count       = var.node_or_fargate == "nodes" ? 1 : 0
  name_prefix = "${local.cluster_name}-nodes-"

  vpc_security_group_ids = [aws_security_group.node_group[0].id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 obligatorio
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.cluster_name}-node"
    }
  }

  tags = {
    Name = "${local.cluster_name}-nodes-lt"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Managed Node Group (only when node_or_fargate = "nodes")
################################################################################

resource "aws_eks_node_group" "this" {
  count = var.node_or_fargate == "nodes" ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-nodes"
  node_role_arn   = data.aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets
  instance_types  = var.node_group_instance_types
  capacity_type   = var.node_group_capacity_type

  launch_template {
    id      = aws_launch_template.nodes[0].id
    version = aws_launch_template.nodes[0].latest_version
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name = "${local.cluster_name}-nodes"
  }

  depends_on = [
    module.nat_instance,
    aws_security_group_rule.nodes_ingress_self,
    aws_security_group_rule.nodes_ingress_cluster,
    aws_security_group_rule.nodes_ingress_frontend_nodeport,
    aws_security_group_rule.nodes_egress_all,
  ]
}

################################################################################
# CoreDNS Add-on
# Proporciona resolucion DNS dentro del cluster. Los pods usan CoreDNS para
# resolver nombres de servicios internos (e.g., my-svc.default.svc.cluster.local).
# En modo Fargate requiere computeType = "Fargate".
################################################################################

data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = data.aws_eks_addon_version.coredns.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = var.node_or_fargate == "fargate" ? jsonencode({
    computeType = "Fargate"
  }) : null

  tags = {
    Name = "${local.cluster_name}-coredns"
  }

  depends_on = [
    aws_eks_fargate_profile.this,
    aws_eks_node_group.this,
  ]
}

################################################################################
# VPC-CNI Add-on
# Plugin de networking que asigna IPs de la VPC directamente a los pods,
# permitiendo comunicacion nativa entre pods y otros recursos de la VPC.
# En modo Fargate habilita Pod ENI para que cada pod tenga su propia interfaz.
################################################################################

data "aws_eks_addon_version" "vpccni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "vpccni" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpccni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = var.node_or_fargate == "fargate" ? jsonencode({
    enablePodEni = true
  }) : null

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
  tags = {
    Name = "${local.cluster_name}-vpc-cni"
  }
}

################################################################################
# kube-proxy Add-on
# Mantiene las reglas de red (iptables/ipvs) en cada nodo para enrutar el
# trafico de los Services de Kubernetes hacia los pods correspondientes.
################################################################################

data "aws_eks_addon_version" "kubeproxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}


resource "aws_eks_addon" "kubeproxy" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kubeproxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${local.cluster_name}-kube-proxy"
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
}

#################################################################################
# EBS CSI Driver Add-on (DESHABILITADO - requiere OIDC/IRSA)
# Permite crear y montar volumenes EBS como PersistentVolumes en los pods.
# Necesario para workloads stateful (bases de datos, caches).
# No disponible en cuentas lab sin permisos IAM para crear OIDC providers.
#################################################################################
# 
# data "aws_eks_addon_version" "ebs-csi-driver" {
#   addon_name         = "aws-ebs-csi-driver"
#   kubernetes_version = aws_eks_cluster.this.version
#   most_recent        = true
# }}
# 
# resource "aws_eks_addon" "aws_ebs_csi_driver" {
#   cluster_name                = aws_eks_cluster.this.name
#   addon_name                  = "aws-ebs-csi-driver"
#   addon_version               = data.aws_eks_addon_version.ebs-csi-driver.ebs-csi-driver.version
#   resolve_conflicts_on_create = "OVERWRITE"
#   resolve_conflicts_on_update = "OVERWRITE"
#   service_account_role_arn    = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/AWS-EBS-CSI-Driver"
# 
#   tags = {
#     Name = "${local.cluster_name}-aws-ebs-csi-driver"
#   }
# 
#   depends_on = [
#     aws_eks_cluster.this,
#     aws_eks_node_group.this,
#   ]
# }

################################################################################
# Metrics Server Add-on
# Recolecta metricas de CPU y memoria de los pods y nodos. Requerido para
# que funcione kubectl top, Horizontal Pod Autoscaler (HPA) y Vertical Pod
# Autoscaler (VPA).
################################################################################

data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.metrics_server.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = {
    Name = "${local.cluster_name}-metrics-server"
  }

  depends_on = [
    aws_eks_cluster.this,
    aws_eks_node_group.this,
  ]
}
