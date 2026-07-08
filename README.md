# Tienda de Perritos — CI/CD en AWS EKS

Plataforma de ejemplo (frontend + backend + base de datos relacional) para la Evaluación
Final Transversal de Introducción a Herramientas DevOps (ISY1101). El ciclo completo de
integración, pruebas, empaquetado y despliegue está automatizado con GitHub Actions,
publicando imágenes en Amazon ECR y desplegando en un clúster Amazon EKS.

## Arquitectura

```
                 ┌──────────────┐
   Internet ───▶ │   frontend   │  nginx + SPA estática
                 │  (Service:   │
                 │ LoadBalancer)│
                 └──────┬───────┘
                         │ proxy_pass /api/*
                         ▼
                 ┌──────────────┐
                 │   backend    │  Node.js + Express
                 │ (Service:    │
                 │  ClusterIP)  │
                 └──────┬───────┘
                         │ mysql2
                         ▼
                 ┌──────────────┐
                 │      db      │  MySQL 8
                 │ (Service:    │
                 │  ClusterIP)  │
                 └──────────────┘
```

Los tres componentes corren en contenedores independientes, conectados por una red
interna (`tienda-net` en Docker Compose, namespace `tienda` en Kubernetes). El frontend
nunca habla directo con la base de datos: todo pasa por la API del backend.

Diagrama de despliegue completo (VPC, subredes, EKS, ECR, CloudWatch): ver
[`docs/arquitectura.svg`](docs/arquitectura.svg), incluido también en el informe.

## Informe

El informe técnico (formato Word) que justifica las decisiones de arquitectura,
contenerización, CI/CD, infraestructura, secretos, observabilidad, seguridad y
orquestación está en [`docs/Informe_Tienda_Perritos_EFT.docx`](docs/Informe_Tienda_Perritos_EFT.docx).

## Estructura del repositorio

```
.
├── frontend/            # nginx + SPA estática, proxy /api/ hacia el backend
├── backend/              # API REST (Express) sobre MySQL
├── db/                    # Imagen MySQL con seed de datos (init.sql)
├── docker-compose.yml      # Orquestación local de los 3 servicios
├── k8s/                     # Manifiestos de despliegue en Kubernetes (EKS)
├── tf-aws-eks-main/          # Terraform: VPC, EKS, ECR, addons
└── .github/workflows/         # Pipelines de CI/CD (build/test/push/deploy)
```

## Desarrollo local

```bash
docker compose up -d --build
curl http://localhost/api/productos
curl http://localhost/api/health
```

Esto levanta `db` (MySQL con seed de productos), `backend` (puerto 3001) y `frontend`
(puerto 80, sirviendo la SPA y haciendo proxy de `/api/` al backend).

## CI/CD (GitHub Actions)

Cada componente tiene su propio workflow, disparado por cambios en su carpeta
(`frontend/**`, `backend/**`, `db/**`) o manualmente (`workflow_dispatch`):

- **`cicd-tienda-backend.yml`**: instala dependencias y corre tests (`npm test`), build
  y push de la imagen a ECR, y actualiza el `Deployment` en EKS.
- **`cicd-tienda-frontend.yml`**: build de la imagen, smoke test (levanta el contenedor y
  valida que responda por HTTP), push a ECR y actualización del `Deployment`.
- **`cicd-tienda-db.yml`**: build de la imagen, smoke test (espera a que MySQL acepte
  conexiones y valida el seed de datos), push a ECR y actualización del `Deployment`.
- **`deploy-infra.yml`**: aplica la infraestructura Terraform (VPC, EKS, ECR) y luego
  aplica los manifiestos de `k8s/` sustituyendo las URLs de ECR generadas por Terraform.
- **`destroy-infra.yml`**: destruye la infraestructura (requiere confirmación manual).

### Variables y secrets requeridos en el repositorio de GitHub

**Secrets** (credenciales temporales del AWS Academy Learner Lab; deben renovarse cuando
expira la sesión):

- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_SESSION_TOKEN`

**Variables** (`vars`):

- `ENVIRONMENT`, `PROJECT_NAME`, `OWNER_NAME`, `AWS_REGION`
- `VPC_CIDR`, `KUBERNETES_VERSION`, `NODE_OR_FARGATE`
- `NODE_GROUP_INSTANCE_TYPES`, `NODE_GROUP_CAPACITY_TYPE`
- `APPS_REPOSITORY` (lista JSON, p.ej. `["frontend","backend","db"]`)
- `BUCKET_BACKEND`, `KEY_BACKEND` (backend remoto de Terraform en S3)

Ver también [`tf-aws-eks-main/README.md`](tf-aws-eks-main/README.md) para el detalle de
la infraestructura.

## Orden de despliegue

1. `deploy-infra.yml` (manual o vía PR sobre `tf-aws-eks-main/**`): crea VPC, EKS, ECR y
   aplica los manifiestos base de `k8s/` (namespace, configmap, secrets, deployments,
   HPA).
2. `cicd-tienda-*.yml`: en cada push a `frontend/`, `backend/` o `db/`, construyen la
   imagen, la validan y actualizan el `Deployment` correspondiente en el clúster ya
   desplegado.

## Seguridad y configuración

- Imágenes base minimalistas (`node:18-alpine`, `nginx:alpine`, `mysql:8`); el backend usa
  un Dockerfile multietapa y corre como usuario no root.
- Escaneo de vulnerabilidades activado en ECR (`scan_on_push`).
- 3 Security Groups explícitos y restrictivos (`tf-aws-eks-main/security_groups.tf`): uno
  para el plano de control EKS, uno para los nodos (Launch Template propio) y uno para el
  Load Balancer público del frontend — ver detalle en
  [`tf-aws-eks-main/README.md`](tf-aws-eks-main/README.md#security-groups-security_groupstf).
- IMDSv2 obligatorio y volumen EBS cifrado en las instancias del node group.
- Credenciales de base de datos gestionadas vía `k8s/secrets.yaml` (Kubernetes Secret) y
  GitHub Secrets para las credenciales de AWS — nunca hardcodeadas en el código fuente.
- El acceso al clúster EKS usa los roles IAM del Learner Lab con permisos acotados al
  ciclo de vida de la infraestructura definida en Terraform.
- Métricas y logs de recursos en CloudWatch Container Insights (`k8s/cloudwatch-agent.yaml`),
  vía el rol de instancia del node group (el Lab no soporta IRSA/OIDC) — deshabilitado por
  defecto (`enable_node_cloudwatch_metrics = false`) para que el pipeline nunca falle por un
  permiso de IAM que el Lab podría no otorgar; se activa sin tocar código si el rol lo permite.
