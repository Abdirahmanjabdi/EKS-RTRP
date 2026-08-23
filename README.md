# Real-Time Risk Platform (RTRP) — EKS

A cloud-native trade risk platform migrated from ECS Fargate to Amazon EKS.
Four microservices, fully deployed on Kubernetes with Helm, GitOps via
ArgoCD, automated DNS and TLS, and full-stack monitoring — built
milestone by milestone as a hands-on AWS/Kubernetes/Terraform learning
project.

The original platform (M1–M4) ran on ECS Fargate. This repo is the EKS
migration: compute moved to Kubernetes, backend data services (RDS
PostgreSQL, ElastiCache Redis, Amazon MQ) stay as managed AWS services.

## Project Overview

RTRP accepts trade executions over an HTTPS API and publishes them as events
to a message broker. Downstream services never call each other directly —
only through the broker — which is what lets four independently deployable
services scale, restart, and fail without taking each other down.

- **Trade API** — FastAPI service. `GET /health` for liveness;
  `POST /trades` validates a trade, persists it to Postgres, caches the
  latest risk figure in Redis, and publishes a `trade.created` event to
  RabbitMQ. The only public-facing service.
- **Risk Engine** — a standalone RabbitMQ consumer with no inbound network
  access. Computes a risk figure per trade, persists and caches the result,
  and publishes a `risk.computed` event for downstream consumers.
- **ML Inference** — consumes `risk.computed`, keeps a rolling per-symbol
  window in Redis, and runs `IsolationForest` against each new value to flag
  statistically unusual exposure.
- **Alerting** — a single queue bound to both the threshold rule
  (`risk.computed` over $50k) and ML Inference's flagged anomalies, fanning
  both into one SNS topic, one Postgres audit table, and one Prometheus
  counter.

## Architecture

![RTRP Architecture](docs/diagrams/rtrp-traffic-flow.png)

Traffic flows through the system in two paths:

**Live request path:** Client → Route 53 → NLB → NGINX Ingress Controller →
Trade API. This is the only synchronous HTTPS call. NGINX routes based on
hostname — `eks.lab.sentineltrading.org` hits Trade API,
`argocd.lab.sentineltrading.org` hits ArgoCD, `grafana.lab.sentineltrading.org`
hits Grafana.

**Async event path:** Trade API publishes to RabbitMQ (Amazon MQ). Risk
Engine consumes and republishes. ML Inference and Alerting consume in turn.
No service calls another's port directly — only the broker.

Key architectural points:

- All four services run as K8s Deployments in the `default` namespace,
  deployed via a single Helm chart (`helm/rtrp-app`).
- Only Trade API has a Service (ClusterIP) and Ingress. The other three are
  pure background consumers with no inbound traffic — by design.
- Backend services (RDS, ElastiCache, Amazon MQ) remain as managed AWS
  resources inside the VPC. Only compute moved to Kubernetes.
- No static AWS credentials anywhere. Pods authenticate via IRSA, CI via
  GitHub OIDC.
- TLS is fully automated: CertManager issues Let's Encrypt certs via DNS-01
  challenges against Route53. ExternalDNS auto-creates DNS records from
  Ingress hostnames.

## ECS → EKS Migration

| ECS Concept | EKS Equivalent |
|---|---|
| Task Definition | Deployment |
| ECS Service (desired count) | Deployment `replicas` |
| ALB + Target Group | NGINX Ingress Controller + NLB |
| Per-task Security Groups | NetworkPolicies |
| Service Discovery (Cloud Map) | K8s DNS (`trade-api.default.svc.cluster.local`) |
| Task Role (per-service IAM) | IRSA (IAM Roles for Service Accounts) |
| CloudWatch (awslogs) | Prometheus + Grafana |
| ACM Certificate | CertManager + Let's Encrypt |
| Fargate (serverless) | Managed Node Groups (EC2) |
| CodePipeline / ECS deploy | GitHub Actions + ArgoCD (GitOps) |

## Infrastructure

| Component | Detail |
|---|---|
| **Region** | eu-north-1 (Stockholm) |
| **VPC** | 3 public + 3 private subnets across 3 AZs |
| **EKS cluster** | rtrp-eks, K8s 1.31, 3x t3.small managed node group |
| **Ingress** | NGINX Ingress Controller, auto-provisioned NLB in public subnets |
| **DNS** | ExternalDNS → Route53, auto-managed A records |
| **TLS** | CertManager, Let's Encrypt, DNS-01 via Route53 |
| **GitOps** | ArgoCD, auto-sync from `main`, self-heal + prune enabled |
| **Monitoring** | kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter) |
| **State backend** | S3 + DynamoDB (remote locking) |
| **IaC** | Terraform with reusable modules (`infra/modules/`) |

## GitOps Deployment Flow

![GitOps Flow](docs/diagrams/gitops-flow.png)

1. Developer pushes code to `main`
2. GitHub Actions: lint (ruff + helm lint) → build 4 Docker images (parallel
   matrix) → push to ECR with `$GITHUB_SHA` tag
3. GitHub Actions: update `global.image.tag` in `values.yaml` → commit + push
4. ArgoCD detects the change → syncs to cluster → rolling update
5. ArgoCD reports `Synced + Healthy`

CI never runs `kubectl apply` or `helm upgrade` directly. It updates Git,
and ArgoCD reconciles — that's the GitOps contract.

## App Demo

`https://eks.lab.sentineltrading.org/health` → `{"status": "ok"}`

ArgoCD: `https://argocd.lab.sentineltrading.org`

Grafana: `https://grafana.lab.sentineltrading.org`

## Local Setup

Requires Python 3.12+.

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py
```

`GET /health` works immediately. `POST /trades` requires `RABBITMQ_URL`,
`RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD` — the broker is only reachable from
inside the VPC, so end-to-end testing requires a deployed cluster or a local
RabbitMQ container.

Run tests:

```bash
pytest -v
```

Run via Docker:

```bash
docker build -t rtrp-trade-api .
docker run -p 8000:8000 rtrp-trade-api
```

## Project Structure

```
.
├── main.py                       # Trade API (FastAPI)
├── test_main.py                  # Trade API tests
├── Dockerfile                    # Trade API image
├── risk_engine/                  # Risk Engine consumer/publisher
├── ml_inference/                 # Anomaly detection consumer (IsolationForest)
├── alerting/                     # Threshold + ML-anomaly fan-out, SNS publish
├── helm/
│   └── rtrp-app/                 # Helm chart for all 4 services
│       ├── Chart.yaml
│       ├── values.yaml           # Global image config, per-service resources, env vars
│       └── templates/
│           ├── trade-api-deployment.yaml
│           ├── trade-api-service.yaml
│           ├── trade-api-ingress.yaml
│           ├── risk-engine-deployment.yaml
│           ├── ml-inference-deployment.yaml
│           └── alerting-deployment.yaml
├── kubernetes/
│   ├── argocd/
│   │   ├── argocd-ingress.yaml   # ArgoCD UI Ingress with TLS
│   │   └── rtrp-application.yaml # ArgoCD Application (GitOps source)
│   ├── cert-manager/
│   │   └── cluster-issuer.yaml   # Let's Encrypt ClusterIssuer (DNS-01)
│   └── monitoring/
│       └── grafana-ingress.yaml  # Grafana UI Ingress with TLS
├── infra/
│   ├── bootstrap/                # S3 state bucket + DynamoDB lock table
│   ├── vpc/                      # VPC, subnets, NAT gateway, EKS subnet tags
│   ├── eks/                      # EKS cluster, node group, OIDC, IRSA roles
│   ├── ecr/                      # Container image repositories
│   ├── modules/
│   │   ├── vpc/                  # VPC child module
│   │   └── eks/                  # EKS child module (cluster, nodes, IRSA)
│   ├── database/                 # RDS PostgreSQL (unchanged from ECS)
│   ├── cache/                    # ElastiCache Redis (unchanged from ECS)
│   └── messaging/                # Amazon MQ RabbitMQ (unchanged from ECS)
├── docs/
│   ├── architecture.md           # Full architecture documentation
│   ├── diagrams/                 # Lucidchart exports
│   └── adr/                      # Architecture Decision Records
└── .github/workflows/
    ├── terraform.yml             # Plan on PRs, apply on main — infra/** only
    └── app.yml                   # Lint → build → push to ECR → update values.yaml
```

Each `infra/*` directory is an independent Terraform root module with its own
S3 backend key. They're stitched via `terraform_remote_state` reads — `eks`
reads `vpc`'s outputs for subnet IDs and VPC ID. Deploy order:
bootstrap → vpc → eks.

## Pipelines

### Terraform (`terraform.yml`)

- Triggers on `infra/**` changes only
- Plans on PRs (review before merge), applies on push to `main`
- AWS auth via GitHub OIDC — no static credentials

### Application (`app.yml`)

- Triggers on `helm/**` and `services/**` changes
- Lint gate: ruff + helm lint on PRs
- Build: 4 parallel matrix jobs (one per service), push sha-tagged images to ECR
- Deploy: updates `values.yaml` with `$GITHUB_SHA` → ArgoCD auto-syncs

## Kubernetes Namespaces

| Namespace | Contents |
|---|---|
| `default` | RTRP services (trade-api, risk-engine, ml-inference, alerting) |
| `ingress-nginx` | NGINX Ingress Controller |
| `external-dns` | ExternalDNS (Route53 automation) |
| `cert-manager` | CertManager + webhook + cainjector |
| `argocd` | ArgoCD (GitOps controller) |
| `monitoring` | Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics |

## Security

- **IRSA** — ExternalDNS and CertManager authenticate to AWS via OIDC-bound
  IAM roles, scoped to specific ServiceAccounts. No static credentials in
  pods.
- **GitHub OIDC** — CI authenticates to AWS via short-lived OIDC tokens. No
  access keys in GitHub Secrets.
- **Private subnets** — all EKS nodes run in private subnets with no public
  IPs. Outbound traffic goes through NAT gateway.
- **TLS everywhere** — Let's Encrypt certificates on all Ingress endpoints,
  auto-renewed by CertManager before expiry.
- **GitOps** — no direct cluster access needed for deployments. All changes
  are audited in Git with PR review.
