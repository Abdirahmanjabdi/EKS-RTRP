# ADR-002: Use Amazon MQ (managed RabbitMQ) for the Milestone 2 message broker

## Status
Accepted

## Context
Milestone 2 turns the Trade API from a synchronous request/response service
into the entry point of an event-driven pipeline: it publishes each accepted
trade to a queue instead of computing anything itself, and a new Risk Engine
consumer reads from that queue to compute risk. The roadmap commits to
RabbitMQ specifically, over AMQP, rather than an AWS-proprietary queue — so
the open question for M2 is not which broker, but who runs it.

As with ADR-001, this is a solo build in a personal AWS account under a fixed
budget, and the project has an established pattern of trading a managed-service
cost premium for less operational surface when the milestone's real value is
elsewhere (Fargate over self-managed EC2 hosts). For M2, the actual point of
the milestone is the event-driven boundary and the risk-computation logic
behind it — not learning to operate a message broker. Self-hosting RabbitMQ on
ECS Fargate was seriously considered, and initially looked cost-comparable to
Amazon MQ (~$17-25/month either way, based on `mq.t3.micro` pricing). That
comparison turned out to be built on a broker size AWS no longer lets you
create: `mq.t3.micro` was deprecated for new brokers before this ADR was
implemented, and the actual minimum viable RabbitMQ broker (`mq.m7g.medium`)
costs roughly 4-5x more. So this decision is not cost-neutral — it's a
deliberate premium paid to avoid, for this milestone, AWS Cloud Map for
service discovery (the Trade API and Risk Engine need a stable internal
address for a broker that has no business being internet-facing — a pattern
this project doesn't have yet and will need again once M3 adds
Postgres/Redis), EFS for durable storage (Fargate's local storage is
ephemeral), and ownership of RabbitMQ's version and upgrade path. Given the
choice between spending M2's time on broker infrastructure or on the actual
event-driven design, speed and staying inside the project's existing "let AWS
own the undifferentiated part" pattern won out, at a real and non-trivial cost
premium accepted deliberately rather than assumed away.

## Decision
Milestone 2's broker is Amazon MQ for RabbitMQ, deployed as a single-instance
broker (no HA) on `mq.m7g.medium` — the smallest instance type AWS currently
allows for a new RabbitMQ broker (`mq.t3.micro` is deprecated and no longer
creatable; AWS itself labels `m7g.medium` "Evaluation" tier, which is an
honest fit for this milestone), placed in the private subnets already
provisioned by `infra/vpc`. Credentials
are generated with Terraform's `random_password` and stored in AWS Secrets
Manager rather than committed to any `.tf` file or CI variable. This follows
the existing module pattern: a new `infra/messaging` root module with its own
S3 backend key, pulling `vpc_id` and private subnet IDs from `infra/vpc`'s
remote state the same way `infra/ecs` does. The module is added to the
`infra.yml` matrix, and `rtrp-ci-permissions` gets a new statement granting
the `mq:*` actions the CI role doesn't currently have.

## Alternatives considered
- **Self-hosted RabbitMQ on ECS Fargate** — not rejected outright, deferred.
  At the true, corrected cost this is clearly the cheaper path (~$17-25/month
  versus `mq.m7g.medium`'s ~$95-125/month), not the cost-neutral option it
  first appeared to be. Chosen against anyway because it bundles three new
  concerns — service discovery via Cloud Map, durable storage via EFS, and
  RabbitMQ version/upgrade ownership — into a milestone whose real subject is
  the message contract and the Risk Engine, not the broker. The
  service-discovery lesson (genuinely useful groundwork for M5's EKS
  migration, since a Cloud Map-backed internal DNS name is conceptually the
  same thing a Kubernetes `Service` provides) will very likely come up again
  in M3 regardless, so nothing here is lost for good — only resequenced, at a
  real monthly cost for the resequencing.
- **Amazon SQS** — rejected. It's the cheapest, lowest-ops option and would
  need no new Terraform pattern beyond a single `aws_sqs_queue`, but it's
  AWS-proprietary: no exchanges, no routing keys, no AMQP semantics. The
  roadmap already commits to RabbitMQ for this milestone, and swapping it for
  SQS would mean designing the M2 event boundary around a different messaging
  model than planned, not just a different host.
- **Amazon MQ, active/standby (HA)** — rejected for M2. Roughly doubles the
  broker cost for a failover guarantee this milestone doesn't need — a single
  Trade API instance and a single Risk Engine consumer have no HA requirement
  to protect yet. Same logic ADR-001 used to defer EKS: pay for resilience
  when something depends on it, not before.

## Consequences
- Ships M2's event boundary faster: no service-discovery setup, no EFS, no
  RabbitMQ upgrade path to own — effort goes into the message contract (what
  the Trade API publishes) and the Risk Engine's consumer logic, which is the
  actual point of this milestone.
- Cost: adds roughly $95-125/month (single-instance `mq.m7g.medium`,
  estimated from AWS's published `mq.m7g.large` rate — verify the exact
  eu-north-1 figure against the AWS Pricing Calculator before applying) on
  top of the ~$60-70/month M1 already runs, pushing the total run rate toward
  ~$160-200/month. This is a real, deliberate premium over self-hosting
  (~$17-25/month), accepted for less operational surface during this
  milestone — not a cost-neutral choice, and worth re-checking against actual
  billing once the broker is live rather than trusting this estimate.
- New skill/surface introduced deliberately: this is the project's first use
  of Secrets Manager, needed because Amazon MQ requires broker credentials at
  creation time and hardcoding them was never on the table.
- New CI gap to close on day one of implementation: `rtrp-ci-permissions` has
  no `mq:*` actions yet, so the first `terraform plan` against
  `infra/messaging` will fail authorization the same way `ecr` and `dns` did
  when the CI matrix first covered them — expected, not a surprise, given the
  pattern already seen twice this project.
- Deferred, not eliminated: the Cloud Map / internal-service-discovery lesson
  this choice avoids for M2 is still on the roadmap — M3's Postgres/Redis (if
  self-hosted rather than RDS/ElastiCache) or a future self-hosted broker
  migration would reintroduce it.
- Vendor lock-in is partial, not total: Amazon MQ's control plane is
  AWS-specific, but the data plane speaks standard AMQP/RabbitMQ, so the
  Trade API and Risk Engine's client code (`pika`/`aio-pika`) is portable.
  Migrating off Amazon MQ later is a Terraform and connection-string change,
  not an application rewrite — a smaller switching cost than ADR-001's
  ECS-to-EKS migration carries.
