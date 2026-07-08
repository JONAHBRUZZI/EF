# Guía de presentación — EFT ISY1101 (10 a 15 minutos)

Repositorio: https://github.com/JONAHBRUZZI/eva_3

La presentación es en dupla, pero **cada estudiante debe fundamentar individualmente**
su parte y responder preguntas del docente por separado. Esta guía divide el tiempo en
bloques y marca, en cada bloque, qué mostrar en pantalla, qué decir, y qué preguntas
típicas de defensa preparar.

## Antes de presentar — checklist de prerrequisitos

- [ ] Renovar `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` / `AWS_SESSION_TOKEN` en
      GitHub Secrets (Settings → Secrets and variables → Actions).
- [ ] Ejecutar `deploy-infra.yml` (workflow_dispatch) y esperar a que termine en verde.
- [ ] Ejecutar los 3 pipelines de aplicación (`cicd-tienda-frontend.yml`,
      `cicd-tienda-backend.yml`, `cicd-tienda-db.yml`) — vía `workflow_dispatch` o
      haciendo un push trivial a cada carpeta.
- [ ] Confirmar que el frontend responde: `kubectl get svc -n tienda frontend` → copiar
      la IP/hostname del `LoadBalancer` y probarla en el navegador.
- [ ] Tener abiertas de antemano (en pestañas separadas): GitHub Actions (runs
      recientes), consola de AWS (EKS, ECR, EC2, CloudWatch), y una terminal con
      `kubectl` configurado (`aws eks update-kubeconfig ...`).
- [ ] Tener el informe (`docs/Informe_Tienda_Perritos_EFT.docx`) y el diagrama
      (`docs/arquitectura.svg`) a mano para referenciar si el docente pide detalle.

Sin esto, el punto "Orquestación y Despliegue en la Nube" (evidencia de despliegue
activo) no se puede demostrar en vivo — es el bloque más grande de la rúbrica (20%).

## Reparto sugerido entre la dupla

Repartan por bloques completos, no por frases sueltas, para que cada quien domine su
tramo y pueda responder preguntas de defensa sobre él sin depender del compañero:

- **Estudiante A**: Repositorio + Contenedores + Pipeline CI/CD (bloques 1-3, ~7 min)
- **Estudiante B**: Infraestructura en la nube + Orquestación/Escalabilidad (bloques 4-5, ~7 min)
- Ambos participan en la demo en vivo (bloque 3.3 y 4.1) y en el cierre.

---

## Bloque 1 — Repositorio (1 min)

**Mostrar:** la URL del repo en el navegador, la pestaña "Insights → Network" o
simplemente `git log --oneline` en terminal.

**Decir:**
- "El repositorio es público: `github.com/JONAHBRUZZI/eva_3`."
- "Trabajamos sobre `main`; el historial de commits usa mensajes descriptivos con
  prefijos `feat:`, `fix:`, `docs:` (convención de commits convencionales)."
- Mostrar `git log --oneline -15` y señalar 2-3 mensajes que expliquen decisiones
  reales (ej. `fix: usar find en vez de glob para sed`, `feat: agregar HPA y resource
  limits a deployments K8s`).

**Nota honesta para la defensa:** si el docente pregunta por ramas de feature, la
respuesta correcta es: "trabajamos directamente sobre `main` con commits atómicos y
descriptivos; no usamos ramas de feature separadas en este proyecto." No inventar una
estrategia de branching que no existe.

---

## Bloque 2 — Contenedores (2-3 min)

**Mostrar:** `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml`.

**Decir sobre el Dockerfile del backend (multietapa):**
```dockerfile
FROM node:18-alpine AS deps      # etapa 1: instala dependencias (npm ci --omit=dev)
...
FROM node:18-alpine AS runtime   # etapa 2: solo copia node_modules + codigo fuente
...
RUN addgroup -S app && adduser -S app -G app
USER app                          # el proceso corre sin privilegios de root
```
- "Usamos `node:18-alpine` como imagen base minimalista, no la imagen completa de
  Node, para reducir superficie de ataque y tamaño."
- "El build es multietapa: la etapa `deps` instala dependencias con `npm ci`
  (instalación reproducible desde `package-lock.json`), y la etapa `runtime` final
  solo copia lo que hace falta para ejecutar — no arrastra herramientas de build."
- "El contenedor corre como usuario no root (`app`), no como root."
- "Cada componente tiene su `.dockerignore` para no filtrar `node_modules` o `.git`
  al contexto de build."

**Decir sobre `docker-compose.yml`:**
- "Los 3 servicios (`db`, `backend`, `frontend`) comparten la red `tienda-net`."
- "El backend espera a que la base de datos esté *healthy* (`depends_on: condition:
  service_healthy`) antes de arrancar, evitando errores de conexión."

**Demo en vivo (30-45 seg):**
```bash
docker compose up -d --build
curl http://localhost/api/productos
curl http://localhost/api/health
docker compose down
```
Muestra el JSON de productos en pantalla — es evidencia tangible de que el entorno
local funciona de punta a punta.

---

## Bloque 3 — Pipeline de CI/CD (3-4 min)

**Mostrar:** `.github/workflows/cicd-tienda-backend.yml` (o el de frontend/db) abierto
en GitHub, y la pestaña "Actions" con una corrida exitosa expandida.

### 3.1 Explicar las etapas

- **Build**: "cada workflow construye la imagen Docker del componente que cambió."
- **Test**: "el backend corre `npm test` — un test real con `node:test` contra el
  endpoint `/api/health`, sin depender de la base de datos. Frontend y DB hacen un
  *smoke test*: levantan el contenedor recién construido y verifican que responda
  (HTTP 200 en frontend; una consulta SQL real en la base de datos) antes de seguir."
- **Push**: "login en ECR con `aws-actions/amazon-ecr-login`, y se publica la imagen
  con **dos tags**: el SHA del commit (trazabilidad exacta) y `latest`."
- **Deploy**: "`aws eks update-kubeconfig` autentica `kubectl` contra el cluster,
  `kubectl set image` actualiza el Deployment con la imagen nueva, y `kubectl rollout
  status` verifica que el rollout termine antes de marcar el job como exitoso."

### 3.2 Gestión de secretos

- "Las credenciales de AWS (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_SESSION_TOKEN`) están en **GitHub Secrets**, nunca en el código. Son
  credenciales temporales del AWS Academy Learner Lab, por eso hay que renovarlas
  cuando expira la sesión."
- "Los valores no sensibles (región, nombre del proyecto, tipo de instancia, etc.)
  están en **GitHub Variables** (`vars`), separados de los secrets."
- "Las credenciales de la base de datos están en un `Secret` de Kubernetes
  (`k8s/secrets.yaml`), montadas como variables de entorno vía `secretKeyRef` —
  nunca escritas directamente en el manifiesto del Deployment."

### 3.3 Demo / evidencia (en vivo o con capturas de respaldo)

- Abrir una corrida exitosa en GitHub Actions y mostrar el log del paso "Build, tag y
  push a ECR" con las líneas `Pushed` y el `digest`.
- Abrir la consola de AWS → ECR → repositorio `backend` (o `frontend`/`db`) y mostrar
  las imágenes listadas con sus tags (SHA + `latest`) y el resultado del escaneo de
  vulnerabilidades (`scan_on_push`).
- Mostrar el log del paso "Verificar rollout" con la línea
  `deployment "backend" successfully rolled out`.

> Evidencia de respaldo si algo falla en vivo: la corrida `workflow_dispatch
> #28141722640` (25-06-2026) del pipeline de DB, con el push exitoso a ECR
> (`digest: sha256:226713e8...`) y el rollout completo — está documentada en el
> informe, sección 8.1.

---

## Bloque 4 — Infraestructura en la nube (3-4 min)

**Mostrar:** consola de AWS (VPC, EC2, EKS) y el diagrama (`docs/arquitectura.svg`).

### 4.1 Arquitectura

- "Todo corre dentro de una VPC (`10.10.0.0/24`) con subredes públicas y privadas en
  2 zonas de disponibilidad."
- "Las subredes públicas tienen salida directa a internet (Internet Gateway); las
  privadas salen a través de una NAT Instance propia (en vez de un NAT Gateway
  administrado, para reducir costo en el Lab)."
- "El cluster EKS corre en las subredes públicas (para el endpoint de la API), y los
  nodos (EC2) corren en las subredes privadas."
- "3 Security Groups explícitos, cada uno con reglas acotadas: uno para el plano de
  control (solo 443 desde la VPC), uno para los nodos (solo tráfico entre nodos, del
  plano de control, y del Load Balancer en un puerto fijo), y uno para el Load
  Balancer público (solo el puerto 80 desde internet, egress solo hacia los nodos)."

### 4.2 Demo en vivo

```bash
kubectl get nodes -o wide
kubectl -n tienda get all
kubectl get hpa -n tienda
```
- Mostrar los nodos EC2 corriendo, los pods de `frontend`/`backend`/`db`, los
  Services (`ClusterIP` para backend/db, `LoadBalancer` para frontend) y el estado
  del HPA (réplicas actuales vs. objetivo de CPU).
- Abrir la URL/IP del `LoadBalancer` en el navegador y mostrar la app funcionando.
- En la consola de AWS: mostrar el cluster EKS (pestaña "Compute" con los nodos), y
  el grupo de instancias EC2 asociado.

### 4.3 IAM

- "Terraform nunca crea roles nuevos: solo **referencia por nombre** los roles ya
  provistos por el Learner Lab (`LabEksClusterRole`, `LabEksNodeRole`), porque el Lab
  no permite crear roles IAM propios."

---

## Bloque 5 — Orquestación y escalabilidad (2 min)

**Decir — por qué EKS y no un despliegue manual sobre EC2:**
- "Autoescalado nativo: el HPA ajusta automáticamente las réplicas de frontend y
  backend según el uso real de CPU — con EC2 manual habría que escribir scripts
  propios para eso."
- "Self-healing: si un pod falla, Kubernetes lo recrea solo, sin intervención
  manual."
- "Actualizaciones sin downtime: `kubectl set image` + `rollout status` hacen un
  rolling update controlado; en EC2 manual habría que reemplazar procesos a mano,
  con riesgo real de caída del servicio."
- "El mismo modelo de contenedores que usamos en desarrollo local (Docker Compose)
  se reutiliza en producción con los mismos Dockerfiles — evita el clásico
  'funciona en mi máquina'."

**Mencionar (si preguntan) el punto de observabilidad:**
- "Además de los logs del pipeline en GitHub Actions, el cluster envía los logs del
  plano de control a CloudWatch. Agregamos también un agente de CloudWatch
  (Container Insights) para métricas de CPU/memoria por pod y nodo — como el
  Learner Lab no soporta IRSA/OIDC, ese agente usa el rol de instancia del node
  group en vez de un rol por servicio, y está detrás de una variable de Terraform
  deshabilitada por defecto para no arriesgar el resto del pipeline si el Lab no
  permite adjuntar esa policy."

---

## Preguntas de defensa esperables (y respuesta corta sugerida)

- **¿Por qué EKS y no ECS?** — "EKS nos da control total sobre el modelo de
  objetos de Kubernetes (Deployments, Services, HPA) que ya conocíamos del curso;
  ECS sería una alternativa válida pero con un modelo de orquestación distinto
  (Task Definitions en vez de Pods)."
- **¿Por qué no tienen Security Groups en un inicio y ahora sí?** — "Al principio
  dependíamos de los SG por defecto de EKS y del módulo de VPC. Hicimos una
  auditoría posterior y agregamos 3 SG explícitos con reglas mínimas por capa,
  documentados en `security_groups.tf`."
- **¿Qué pasa si falla el pipeline a mitad de camino?** — "Todos los recursos son
  declarativos e idempotentes: un `terraform apply` interrumpido (por ejemplo, por
  la expiración de las credenciales temporales del Lab) se puede reintentar sin
  limpieza manual. Además, componentes no críticos como el agente de CloudWatch
  usan `continue-on-error` para no bloquear el resto del despliegue."
- **¿Por qué no usan AWS Secrets Manager?** — "El Learner Lab no da permisos para
  IRSA/OIDC ni para crear roles IAM granulares por servicio; usamos GitHub Secrets
  para las credenciales de AWS y Kubernetes Secrets para las de la base de datos,
  que es lo disponible en este entorno."
- **¿Cómo escala la base de datos?** — Ser honestos: "la base de datos no tiene HPA
  ni almacenamiento persistente (usa `emptyDir`, no un volumen EBS), porque el
  Learner Lab tiene deshabilitado el EBS CSI Driver al no soportar IRSA. Es una
  limitación documentada del entorno, no una omisión."

## Cierre (30 seg)

- "El código completo, la infraestructura como código, los manifiestos de
  Kubernetes y el informe técnico están en el repositorio público. Quedamos
  disponibles para profundizar en cualquier punto."
