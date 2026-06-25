# EKS Fargate / Nodes

Infraestructura EKS desplegada con Terraform. Soporta dos modos de compute: Fargate profiles o Managed Node Groups, controlado por una sola variable.

## Recursos Creados

- VPC con subnets publicas y privadas (2 AZs)
- NAT Instance para salida a internet desde subnets privadas
- EKS Cluster con acceso API y ConfigMap
- Fargate Profile (modo fargate) o Managed Node Group (modo nodes)
- IAM Roles (usa LabEksClusterRole y LabEksNodeRole existentes)
- CoreDNS Add-on (configurado automaticamente para el compute type)
- OIDC Provider para IRSA
- Application Load Balancer (publico, gestionado por Terraform)
- CloudWatch Log Group para logs del control plane

## Prerequisitos

- Terraform >= 1.3.0
- AWS CLI configurado con un perfil valido
- Bucket S3 para backend de estado remoto
- Roles IAM existentes: LabEksClusterRole, LabEksNodeRole

## Uso

```bash
# Inicializar con backend remoto
terraform init -backend-config=backend.hcl

# Validar configuracion
terraform validate

# Planificar cambios
terraform plan --out tfplan --var-file=terraform.tfvars

# Aplicar
terraform apply tfplan

# Configurar kubectl
aws eks update-kubeconfig --region us-east-1 --name eks-lab-eks-fargate

# Destruir
terraform destroy --var-file=terraform.tfvars
```

## Variables Principales

| Variable | Descripcion | Default |
|----------|-------------|---------|
| `environment` | Nombre del ambiente | - |
| `project_name` | Nombre del proyecto | - |
| `aws_region` | Region AWS | - |
| `vpc_cidr` | CIDR block para la VPC | - |
| `kubernetes_version` | Version de Kubernetes | `1.35` |
| `node_or_fargate` | Tipo de compute: `nodes` o `fargate` | `fargate` |
| `node_instance_types` | Tipos de instancia para node group | `["t3.medium"]` |
| `node_desired_size` | Cantidad deseada de nodos | `2` |
| `node_min_size` | Minimo de nodos | `1` |
| `node_max_size` | Maximo de nodos | `3` |

## Compute Toggle

| `node_or_fargate` | Comportamiento |
|---|---|
| `fargate` | Crea Fargate Profile con selectors configurables. CoreDNS se configura para Fargate. |
| `nodes` | Crea Managed Node Group con EC2 instances. CoreDNS corre en los nodos. |

## Conectar servicios al ALB

El ALB se gestiona por Terraform. Para conectar pods al target group, usa TargetGroupBinding:

```yaml
apiVersion: elbv2.k8s.aws/v1beta1
kind: TargetGroupBinding
metadata:
  name: my-app
spec:
  serviceRef:
    name: my-app-service
    port: 80
  targetGroupARN: <alb_target_group_arn>
```

## CI/CD (GitHub Actions)

- `deploy.yml` - Despliega la infraestructura. Crea un issue al finalizar para disparar el destroy.
- `destroy.yml` - Destruye la infraestructura. Requiere confirmacion manual.

### Secrets requeridos

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

### Variables de repositorio requeridas

- `ENVIRONMENT`, `PROJECT_NAME`, `OWNER_NAME`, `AWS_REGION`
- `VPC_CIDR`, `KUBERNETES_VERSION`, `NODE_OR_FARGATE`
- `BUCKET_BACKEND`, `KEY_BACKEND`

## Estructura del Proyecto

```
eks-fargate/
  .github/workflows/
    deploy.yml
    destroy.yml
  backend.hcl
  main.tf
  outputs.tf
  providers.tf
  variables.tf
  terraform.tfvars
```
