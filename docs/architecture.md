# RTRP Architecture — EKS Migration

## System Overview

The Real-Time Risk Platform (RTRP) is a 4-service trading platform migrated from AWS ECS Fargate to Amazon EKS. The platform processes trades in real-time, evaluates risk, runs ML-based inference, and triggers alerts based on configurable thresholds.

Only compute moved to Kubernetes. Backend data services (RDS PostgreSQL, ElastiCache Redis, Amazon MQ RabbitMQ) remain as managed AWS services — keeping operational complexity where AWS handles it best.

### Services

| Service | Type | Port | Role |
|---|---|---|---|
| **Trade API** | FastAPI (public-facing) | 8000 | REST API for trade submission, health checks, external entry point |
| **Risk Engine** | RabbitMQ consumer | 8001 | Evaluates trade risk in real-time based on position and market data |
| **ML Inference** | RabbitMQ consumer | 8002 | Runs ML models against trade data for anomaly detection |
| **Alerting** | RabbitMQ consumer | 8003 | Monitors risk thresholds and sends alerts via SNS |

### Traffic Flow

![RTRP Traffic Flow](diagrams/rtrp-traffic-flow.png)

<!-- Lucidchart diagram — export as PNG to docs/diagrams/rtrp-traffic-flow.png

Diagram elements:
- User (actor icon) → HTTPS arrow → Route53 (AWS icon)
- Route53 → A record arrow → NLB (AWS NLB icon, in public subnet)
- NLB → NGINX Ingress Controller (K8s icon, in EKS cluster boundary)
- NGINX → Trade API (container icon, port 8000)
- Trade API → RDS PostgreSQL (AWS RDS icon, outside EKS boundary, label: "managed AWS service")
- Trade API → ElastiCache Redis (AWS ElastiCache icon, outside EKS boundary)
- Trade API → publish arrow → Amazon MQ / RabbitMQ (AWS MQ icon, outside EKS boundary)
- Amazon MQ → consume arrow → Risk Engine (container, port 8001)
- Amazon MQ → consume arrow → ML Inference (container, port 8002)
- Amazon MQ → consume arrow → Alerting (container, port 8003)
- Alerting → publish arrow → Amazon SNS (AWS SNS icon)

Boundaries:
- VPC boundary (outer)
  - Public subnets: NLB
  - Private subnets: EKS cluster boundary containing all 4 services + NGINX
  - Managed services (RDS, ElastiCache, Amazon MQ) inside VPC but outside EKS
- AWS cloud boundary (outermost)
-->

## Infrastructure

### VPC

- **Region:** eu-north-1 (Stockholm)
- **Subnets:** 3 public + 3 private across 3 Availability Zones
- **NAT Gateway:** Single NAT in public subnet for private subnet internet access
- **Subnet tags:** `kubernetes.io/role/elb` (public), `kubernetes.io/role/internal-elb` (private), `kubernetes.io/cluster/rtrp-eks = shared`

### EKS Cluster

- **Cluster name:** rtrp-eks
- **Kubernetes version:** 1.31
- **Node group:** 3x t3.small (managed node group with launch template)
- **Pod limit:** 11 pods per node (ENI-based: 3 ENIs x 4 IPs - 1)
- **Endpoint access:** Public + Private (kubectl from laptop, nodes via private VPC)

### Networking

| Component | Role |
|---|---|
| NGINX Ingress Controller | Routes external HTTP/HTTPS traffic to Services based on hostname |
| Network Load Balancer | Created automatically by ingress-nginx, sits in public subnets |
| ExternalDNS | Watches Ingress resources, auto-creates/updates/deletes Route53 DNS records |
| CertManager | Auto-provisions Let's Encrypt TLS certificates via DNS-01 challenges |

### DNS Records (auto-managed by ExternalDNS)

| Hostname | Points To |
|---|---|
| `eks.lab.sentineltrading.org` | Trade API (NLB) |
| `argocd.lab.sentineltrading.org` | ArgoCD UI (NLB) |
| `grafana.lab.sentineltrading.org` | Grafana UI (NLB) |

### State Management

- **Terraform state:** S3 bucket `rtrp-terraform-state-04b6152c` with DynamoDB lock table `rtrp-terraform-locks`
- **State keys:** `vpc/terraform.tfstate`, `eks/terraform.tfstate`
- **Cross-module references:** `terraform_remote_state` data source reads VPC outputs from EKS config

## Terraform Module Structure

```
infra/
├── bootstrap/          # S3 + DynamoDB state backend
├── vpc/                # Root VPC config (calls modules/vpc)
├── eks/                # Root EKS config (calls modules/eks, reads VPC remote state)
├── ecr/                # ECR repositories
├── modules/
│   ├── vpc/            # VPC, subnets, NAT, route tables, EKS subnet tags
│   └── eks/            # EKS cluster, node group, OIDC, IRSA roles
├── database/           # RDS PostgreSQL (existing, unchanged)
├── cache/              # ElastiCache Redis (existing, unchanged)
└── messaging/          # Amazon MQ RabbitMQ (existing, unchanged)
```

**Deploy order:** bootstrap → vpc → eks (enforced by `terraform_remote_state` dependencies)

## Kubernetes Resources

### Helm Chart

Single Helm chart (`helm/rtrp-app`) deploys all 4 services:

```
helm/rtrp-app/
├── Chart.yaml
├── values.yaml              # Global image registry/tag, per-service config, env vars
└── templates/
    ├── trade-api-deployment.yaml
    ├── trade-api-service.yaml
    ├── trade-api-ingress.yaml   # Conditional, with TLS + cert-manager annotation
    ├── risk-engine-deployment.yaml
    ├── ml-inference-deployment.yaml
    └── alerting-deployment.yaml
```

### Resource Configuration

| Service | Replicas | CPU Request | Memory Request | CPU Limit | Memory Limit |
|---|---|---|---|---|---|
| Trade API | 1 | 100m | 128Mi | 250m | 256Mi |
| Risk Engine | 1 | 100m | 128Mi | 250m | 256Mi |
| ML Inference | 1 | 100m | 128Mi | 250m | 256Mi |
| Alerting | 1 | 100m | 128Mi | 250m | 256Mi |

### Namespaces

| Namespace | Contents |
|---|---|
| `default` | RTRP application services (trade-api, risk-engine, ml-inference, alerting) |
| `ingress-nginx` | NGINX Ingress Controller |
| `external-dns` | ExternalDNS controller |
| `cert-manager` | CertManager + webhook + cainjector |
| `argocd` | ArgoCD server, repo-server, application-controller, redis, dex, notifications |
| `monitoring` | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics |

## GitOps Deployment Flow

ArgoCD manages the RTRP application declaratively from Git.

![GitOps Deployment Flow](diagrams/gitops-flow.png)

<!-- Lucidchart diagram — export as PNG to docs/diagrams/gitops-flow.png

Diagram elements (left-to-right flow):
1. Developer (actor icon) → "git push" arrow → GitHub (GitHub icon)
2. GitHub → "trigger" arrow → GitHub Actions (GH Actions icon)
3. GitHub Actions splits into parallel lanes:
   a. "lint + test" → Ruff + Helm Lint (check icon)
   b. "build + push" → ECR (AWS ECR icon, 4 images in parallel)
   c. "update tag" → values.yaml (file icon)
4. values.yaml → "commit + push" arrow → GitHub
5. GitHub → "detect change (~3 min)" arrow → ArgoCD (ArgoCD logo)
6. ArgoCD → "sync (rolling update)" arrow → EKS Cluster (AWS EKS icon)

Labels:
- Between steps 1-3: "CI (GitHub Actions)"
- Between steps 5-6: "CD (ArgoCD / GitOps)"
- On the ECR box: "tag: $GITHUB_SHA"
-->

### Flow Detail

1. Developer pushes code to `main`
2. GitHub Actions: lint (ruff + helm lint) → build 4 Docker images (parallel matrix) → push to ECR with `$GITHUB_SHA` tag
3. GitHub Actions: update `global.image.tag` in `values.yaml` → commit + push
4. ArgoCD detects the `values.yaml` change (auto-sync within ~3 minutes)
5. ArgoCD compares desired state (Git) vs live state (cluster)
6. ArgoCD creates new ReplicaSets → rolling update → old pods replaced
7. ArgoCD reports `Synced + Healthy`

### ArgoCD Configuration

- **Sync policy:** Automated (no manual SYNC needed)
- **Prune:** Enabled (resources deleted from Git are removed from cluster)
- **Self-heal:** Enabled (manual `kubectl` changes are reverted to match Git)
- **Source:** `helm/rtrp-app` on `main` branch
- **UI:** `https://argocd.lab.sentineltrading.org`

## CI/CD Pipelines

### Pipeline 1: Terraform (`terraform.yml`)
- **Trigger:** `infra/**` changes
- **PR:** `terraform plan` (review before merge)
- **Main push:** `terraform apply` (auto-deploy)
- **Auth:** GitHub OIDC → AWS IAM role (no static credentials)

### Pipeline 2: Application (`app.yml`)
- **Trigger:** `helm/**` and `services/**` changes
- **PR:** Ruff lint + Helm lint
- **Main push:** Build → Push to ECR → Update `values.yaml` → ArgoCD syncs
- **Auth:** GitHub OIDC → AWS IAM role
- **Image tags:** Commit SHA (immutable, traceable)

## Monitoring

### Stack

| Component | Role |
|---|---|
| Prometheus | Metrics collection via pull-based scraping |
| Grafana | Dashboards and visualization |
| Alertmanager | Alert routing and notification |
| node-exporter (DaemonSet) | Host-level metrics (CPU, memory, disk, network) |
| kube-state-metrics | K8s object metrics (deployments, pods, nodes) |

### Key Dashboards

- **Kubernetes / Compute Resources / Cluster** — overall utilization
- **Kubernetes / Compute Resources / Namespace (Pods)** — per-pod CPU/memory
- **Kubernetes / Compute Resources / Node (Pods)** — per-node pod placement
- **Node Exporter / Nodes** — host-level health

### Access

- **Grafana UI:** `https://grafana.lab.sentineltrading.org`

## Security

### Authentication & Authorization

| Component | Auth Method | Details |
|---|---|---|
| ExternalDNS | IRSA | `rtrp-external-dns` role, Route53 permissions |
| CertManager | IRSA | `rtrp-cert-manager` role, Route53 permissions |
| GitHub Actions | OIDC | `rtrp-github-actions` role, ECR push permissions |
| EKS Nodes | Instance role | `rtrp-eks-node-role`, EKS + ECR + CNI policies |

### Security Principles

- **No static AWS credentials anywhere** — IRSA for pods, OIDC for CI
- **Least privilege** — each controller has its own role with only the permissions it needs
- **Private subnets** — all EKS nodes run in private subnets, no public IPs
- **TLS everywhere** — Let's Encrypt certs on all Ingress endpoints, auto-renewed
- **Git-gated deployments** — no direct cluster access needed for deployments, all changes audited in Git

## ECS Fargate → EKS Migration Mapping

| ECS Concept | EKS Equivalent | Notes |
|---|---|---|
| ECS Cluster | EKS Cluster | Different control plane, same concept |
| Task Definition | Deployment | K8s manifest format with pod spec |
| ECS Service (desired count) | Deployment `replicas` | K8s splits run config from networking |
| ALB + Target Group | NGINX Ingress Controller + NLB | Ingress controller creates its own NLB |
| ALB Security Group | N/A | Ingress controller handles this internally |
| Per-task Security Groups | NetworkPolicies | Pod isolation inside the cluster |
| Service Discovery (Cloud Map) | K8s DNS | `trade-api.default.svc.cluster.local` |
| Task Execution Role | Node IAM Role | Nodes pull images, not individual tasks |
| Task Role (per-service) | IRSA | K8s ServiceAccount ↔ IAM Role via OIDC |
| ECS Secrets (valueFrom) | External Secrets Operator | Injects Secrets Manager values into pods |
| CloudWatch (awslogs) | Prometheus + Grafana | Pull-based metrics, stdout captured natively |
| ACM Certificate | CertManager + Let's Encrypt | Auto-provisioned inside the cluster |
| Fargate (serverless) | Managed Node Groups (EC2) | More control, supports DaemonSets |
| ECS Exec | `kubectl exec` | Direct pod shell access |
| CodePipeline | GitHub Actions + ArgoCD | CI builds, GitOps deploys |
