# ADR-001: Use ECS Fargate before EKS

## Status
Accepted

## Context
Milestone 1 of the Real-Time Risk Platform (RTRP) needs to deploy a single
containerised service (the Trade API) to AWS, reachable over HTTPS on a custom
domain, with everything defined as code. The work is solo, by a builder still
working through a Kubernetes module in parallel. Cost is a direct constraint:
this runs in a personal AWS account under a fixed budget. The roadmap already
commits to migrating to Kubernetes (EKS) at Milestone 5, once the Kubernetes
fundamentals are in place. So the question for M1 is narrow: what is the
simplest orchestrator that can run one container in production, behind a load
balancer with TLS, without adding operational or cost burden the milestone
does not need.

## Decision
Milestone 1 deploys on AWS ECS with the Fargate launch type. ECS provides the
orchestration (scheduling, health-based replacement, load-balancer
registration); Fargate removes server management by running containers with no
EC2 instances to provision or patch. The ECS control plane carries no separate
charge, so cost is limited to the Fargate compute the single service uses.

## Alternatives considered
- **EKS now** — rejected for M1, not forever. EKS adds a control-plane charge
  of roughly $0.10/hour (about $73/month) before any workload runs, plus the
  operational load of managing a cluster, its upgrades, and its add-ons. With
  Kubernetes still being learned, taking that on now trades milestone progress
  for complexity one service does not need. Deferred deliberately to M5.
- **EC2-backed ECS** — genuinely cheaper at sustained scale, since you pay raw
  EC2 rates rather than the Fargate premium, and it gives finer host control.
  Rejected because that control means owning the instances: capacity planning,
  patching, scaling the cluster — the same undifferentiated server management
  the earlier EC2-based build already showed is a distraction from the
  application. Fargate trades a compute premium to remove that burden, which is
  the right trade at this scale.
- **Plain EC2 (no orchestrator)** — rejected. A container on a single instance
  with no scheduler, no self-healing, manual everything. It lacks the
  health-based replacement and load-balancer integration that make a deployment
  production-grade — precisely the capabilities this milestone exists to
  demonstrate.

## Consequences
- Ships faster with less operational surface: no servers to patch, a managed
  control plane, so effort goes into the application, the IaC, and the CI/CD
  rather than into running an orchestrator.
- Consolidates recently-learned tools (Docker, Terraform, CI/CD) on a smaller,
  more forgiving surface before Kubernetes raises the difficulty.
- Cost: ECS and its task/service definitions are AWS-specific. This is vendor
  lock-in — leaving AWS would mean rework — and ECS skills transfer less
  directly than Kubernetes, the portable industry standard.
- Planned future work: at Milestone 5 the task and service definitions are
  rewritten as Kubernetes manifests during the EKS migration. Starting on ECS
  is an accepted, scheduled cost, paid down once the Kubernetes module is
  complete.