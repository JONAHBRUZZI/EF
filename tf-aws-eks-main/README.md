# Infraestructura EKS (Tienda de Perritos)

Infraestructura desplegada con Terraform sobre AWS Academy Learner Lab. Soporta dos
modos de compute (Fargate profiles o Managed Node Groups) controlados por una sola
variable, aunque **el modo activo en este proyecto es `nodes`** (ver limitaciones más
abajo).

## Recursos creados

- VPC con subredes públicas y privadas en 2 AZs (`terraform-aws-modules/vpc/aws`)
- NAT Instance propia (no NAT Gateway administrado, para reducir costo en el Lab)
- Cluster EKS con acceso API + ConfigMap, logs de control plane hacia CloudWatch
- Managed Node Group (modo `nodes`) sobre un Launch Template propio, con:
  - Security Group restrictivo (`security_groups.tf`)
  - IMDSv2 obligatorio (`http_tokens = "required"`)
  - Volumen EBS cifrado (gp3, 20 GiB)
- 3 Security Groups explícitos y documentados (ver más abajo)
- Addons EKS: CoreDNS, VPC-CNI, kube-proxy, metrics-server
- 3 repositorios ECR (frontend/backend/db) con escaneo de vulnerabilidades y
  lifecycle policy
- IAM: solo se **referencian** (`data "aws_iam_role"`) los roles ya existentes del
  Learner Lab (`LabEksClusterRole`, `LabEksNodeRole`); Terraform nunca crea roles
  nuevos, porque el Lab no lo permite
- CloudWatch Log Group para logs del control plane (retención 7 días)

## Security Groups (`security_groups.tf`)

| Security Group | A qué se adjunta | Reglas |
|---|---|---|
| `cluster_additional` | Plano de control EKS (`vpc_config.security_group_ids`) | Ingress 443/tcp solo desde la VPC; egress solo hacia la VPC |
| `node_group` | Instancias EC2 del node group (vía Launch Template) | Ingress: todo el tráfico entre nodos (self, para CNI), 1025-65535/tcp desde `cluster_additional` (kubelet/webhooks), y el NodePort fijo (`var.frontend_node_port`, default `30080`) solo desde `frontend_lb`. Egress abierto (necesario para ECR, S3, APIs de AWS con IPs dinámicas) |
| `frontend_lb` | Load Balancer público del `Service frontend` (vía anotación `aws-load-balancer-security-groups`) | Ingress 80/tcp desde `0.0.0.0/0`; egress solo hacia `node_group` en el NodePort fijo |

**Limitación conocida:** el SG `frontend_lb` y su NodePort fijo asumen el modo
`nodes`. En modo `fargate`, un `Service type=LoadBalancer` respaldado por Fargate
no usa NodePort (requeriría AWS Load Balancer Controller con targets tipo IP), por
lo que esa regla de egress está condicionada a `var.node_or_fargate == "nodes"`.

## Observabilidad — CloudWatch Container Insights (opcional)

El Learner Lab no permite crear un OIDC Provider, por lo que **no hay IRSA/Pod
Identity disponible** y el EBS CSI Driver está deshabilitado por el mismo motivo
(ver comentario en `main.tf`). Sin IRSA, no se puede dar permisos de IAM "por
service account" al agente de CloudWatch.

Alternativa implementada: el DaemonSet `k8s/cloudwatch-agent.yaml` usa directamente
el rol de instancia del node group (`LabEksNodeRole`) vía Instance Metadata Service
— el mecanismo clásico de CloudWatch Agent previo a IRSA. Para que funcione, ese rol
necesita la policy administrada `CloudWatchAgentServerPolicy`, lo cual se controla
con:

```
variable "enable_node_cloudwatch_metrics" # default: false
```

Por defecto está en `false` porque varios Learner Labs bloquean
`iam:AttachRolePolicy` incluso sobre roles ya existentes — dejarlo en `false`
garantiza que Terraform nunca falle por un permiso de IAM que el Lab no otorga.
Si el rol del Lab sí lo permite, se activa con `TF_VAR_enable_node_cloudwatch_metrics=true`
(o la variable de repositorio `ENABLE_NODE_CLOUDWATCH_METRICS`), sin tocar el
resto del código.

Si la policy no está adjunta, los pods de `cloudwatch-agent` quedan en
`CrashLoopBackOff` de forma aislada (namespace `amazon-cloudwatch`): esto **no
afecta** a frontend/backend/db ni al resto del pipeline, por diseño (ver
`deploy-infra.yml`, paso `continue-on-error: true`).

## Prerequisitos

- Terraform >= 1.3.0
- AWS CLI configurado con credenciales válidas (del Learner Lab)
- Bucket S3 para backend de estado remoto
- Roles IAM existentes: `LabEksClusterRole`, `LabEksNodeRole`

## Uso local

```bash
# Inicializar con backend remoto
terraform init -backend-config=backend.hcl

# Validar configuracion (no requiere credenciales)
terraform init -backend=false
terraform validate

# Planificar cambios
terraform plan --out tfplan --var-file=terraform.tfvars

# Aplicar
terraform apply tfplan

# Configurar kubectl
aws eks update-kubeconfig --region us-east-1 --name <cluster_name>

# Destruir
terraform destroy --var-file=terraform.tfvars
```

## Variables principales

| Variable | Descripción | Default |
|----------|-------------|---------|
| `environment` | Nombre del ambiente | - |
| `project_name` | Nombre del proyecto | - |
| `owner_name` | Owner aplicado como tag | - |
| `aws_region` | Región AWS | - |
| `vpc_cidr` | CIDR block para la VPC | - |
| `kubernetes_version` | Versión de Kubernetes | `1.35` |
| `node_or_fargate` | Tipo de compute: `nodes` o `fargate` | `fargate` |
| `node_group_instance_types` | Tipos de instancia para el node group | `["t3.small"]` |
| `node_group_capacity_type` | `ON_DEMAND` o `SPOT` | `ON_DEMAND` |
| `apps_repository` | Lista de nombres de repos ECR a crear | `[]` |
| `frontend_node_port` | NodePort fijo del Service frontend (usado por los SG) | `30080` |
| `enable_node_cloudwatch_metrics` | Adjunta `CloudWatchAgentServerPolicy` al rol del node group | `false` |

## Compute Toggle

| `node_or_fargate` | Comportamiento |
|---|---|
| `fargate` | Crea Fargate Profile con selectors configurables. CoreDNS se configura para Fargate. Los Security Groups de `node_group`/`frontend_lb` (NodePort) no aplican en este modo. |
| `nodes` | Crea Managed Node Group sobre un Launch Template propio (SG restrictivo + IMDSv2). Modo soportado end-to-end por el `Service type=LoadBalancer` del frontend. |

## CI/CD (GitHub Actions)

- `.github/workflows/deploy-infra.yml` — Despliega la infraestructura (VPC, EKS,
  ECR, Security Groups) y aplica los manifiestos de `k8s/`, sustituyendo las URLs
  de ECR, el Security Group del LB y el NodePort generados por Terraform.
- `.github/workflows/destroy-infra.yml` — Destruye la infraestructura (requiere
  confirmación manual escribiendo `destroy`).

### Secrets requeridos

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### Variables de repositorio requeridas

- `ENVIRONMENT`, `PROJECT_NAME`, `OWNER_NAME`, `AWS_REGION`
- `VPC_CIDR`, `KUBERNETES_VERSION`, `NODE_OR_FARGATE`
- `NODE_GROUP_INSTANCE_TYPES`, `NODE_GROUP_CAPACITY_TYPE`
- `APPS_REPOSITORY`
- `BUCKET_BACKEND`, `KEY_BACKEND`
- `ENABLE_NODE_CLOUDWATCH_METRICS` (opcional, default `false` si no se define)

## Estructura del proyecto

```
tf-aws-eks-main/
  main.tf               # VPC, NAT, EKS, node group + launch template, addons
  security_groups.tf     # Security Groups explicitos (cluster/nodos/LB)
  ecr.tf                  # Repositorios ECR + lifecycle policy
  variables.tf
  outputs.tf
  providers.tf
  backend.hcl.example
  terraform.tfvars.example
```
