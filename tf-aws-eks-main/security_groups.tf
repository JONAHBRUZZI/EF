################################################################################
# Security Groups explicitos y restrictivos
#
# EKS y el modulo de VPC ya crean Security Groups por defecto (cluster security
# group administrado por AWS, SG por defecto de la VPC). Estos grupos adicionales
# se suman a esos (no los reemplazan) para acotar explicitamente que trafico se
# permite en cada capa, documentando la regla en vez de depender unicamente de
# defaults implicitos.
#
# Capas:
#   1) cluster_additional -> plano de control EKS (API server)
#   2) node_group         -> instancias EC2 del Managed Node Group
#   3) frontend_lb        -> Load Balancer publico del Service "frontend"
################################################################################

resource "aws_security_group" "cluster_additional" {
  name        = "${local.cluster_name}-cluster-additional-sg"
  description = "SG adicional del plano de control EKS: solo permite HTTPS (443) desde la VPC"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${local.cluster_name}-cluster-additional-sg"
  }
}

resource "aws_security_group_rule" "cluster_ingress_https_from_vpc" {
  description       = "HTTPS (API server) desde cualquier host dentro de la VPC (nodos, NAT instance)"
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster_additional.id
}

resource "aws_security_group_rule" "cluster_egress_to_vpc" {
  description       = "El plano de control solo necesita hablar con nodos/pods dentro de la VPC (no con internet directamente)"
  type              = "egress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.cluster_additional.id
}

################################################################################
# Security Group de los nodos (EC2 del Managed Node Group)
################################################################################

resource "aws_security_group" "node_group" {
  count       = var.node_or_fargate == "nodes" ? 1 : 0
  name        = "${local.cluster_name}-nodes-sg"
  description = "SG de los nodos EKS: trafico entre nodos (CNI), desde el plano de control, y desde el LB publico solo al NodePort de la app"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name                                          = "${local.cluster_name}-nodes-sg"
    "kubernetes.io/cluster/${local.cluster_name}" = "owned"
  }
}

resource "aws_security_group_rule" "nodes_ingress_self" {
  count             = var.node_or_fargate == "nodes" ? 1 : 0
  description       = "Trafico entre pods/nodos via CNI (todos los puertos, solo entre miembros de este SG)"
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.node_group[0].id
}

resource "aws_security_group_rule" "nodes_ingress_cluster" {
  count                    = var.node_or_fargate == "nodes" ? 1 : 0
  description              = "Trafico desde el plano de control EKS hacia kubelet (10250) y webhooks de addons"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.cluster_additional.id
  security_group_id        = aws_security_group.node_group[0].id
}

resource "aws_security_group_rule" "nodes_ingress_frontend_nodeport" {
  count                    = var.node_or_fargate == "nodes" ? 1 : 0
  description              = "Solo el Load Balancer publico del frontend puede llegar al NodePort fijo de la app (var.frontend_node_port)"
  type                     = "ingress"
  from_port                = var.frontend_node_port
  to_port                  = var.frontend_node_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend_lb.id
  security_group_id        = aws_security_group.node_group[0].id
}

resource "aws_security_group_rule" "nodes_egress_all" {
  count             = var.node_or_fargate == "nodes" ? 1 : 0
  description       = "Egress abierto: los nodos necesitan alcanzar ECR, S3 (addons), EKS/STS API y DNS con rangos de IP que AWS cambia dinamicamente"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node_group[0].id
}

################################################################################
# Security Group del Load Balancer publico (Service "frontend", type=LoadBalancer)
#
# Se asigna al ELB creado automaticamente por el cloud-provider de Kubernetes via
# la anotacion "service.beta.kubernetes.io/aws-load-balancer-security-groups" en
# k8s/frontend.yaml (sustituida en el pipeline junto con las URLs de ECR).
#
# NOTA - limite conocido en modo "fargate": este SG y su regla de egress solo
# tienen sentido en modo "nodes" (NodePort fijo hacia instancias EC2 reales).
# En modo "fargate" no existen instancias que registrar en un NodePort: el
# Service type=LoadBalancer respaldado por Fargate requeriria el AWS Load
# Balancer Controller con targets de tipo IP (arquitectura distinta, fuera del
# alcance de este cambio). Por eso la regla de egress de este SG esta atada a
# var.node_or_fargate == "nodes" (unico modo soportado hoy por este proyecto,
# y el que esta configurado actualmente en las variables del repositorio).
################################################################################

resource "aws_security_group" "frontend_lb" {
  name        = "${local.cluster_name}-frontend-lb-sg"
  description = "SG del Load Balancer publico: solo expone el puerto 80 hacia internet y solo puede hablar con los nodos en el NodePort de la app"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name = "${local.cluster_name}-frontend-lb-sg"
  }
}

resource "aws_security_group_rule" "frontend_lb_ingress_http" {
  description       = "Trafico web publico (HTTP) hacia el frontend"
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.frontend_lb.id
}

resource "aws_security_group_rule" "frontend_lb_egress_nodeport" {
  count                    = var.node_or_fargate == "nodes" ? 1 : 0
  description              = "El LB solo puede reenviar trafico al NodePort fijo de la app en los nodos, a ningun otro destino"
  type                     = "egress"
  from_port                = var.frontend_node_port
  to_port                  = var.frontend_node_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.node_group[0].id
  security_group_id        = aws_security_group.frontend_lb.id
}
