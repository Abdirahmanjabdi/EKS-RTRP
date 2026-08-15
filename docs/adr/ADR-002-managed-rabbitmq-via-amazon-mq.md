# ADR-002: Use Amazon MQ (managed RabbitMQ) for the Milestone 2 message broker

## Status
Accepted

## Context
Milestone 2 turns the Trade API from a synchronous request/response service
into the entry point of an event-driven pipeline: it publishes each accepted
trade to a queue instead of computing anything itself, and a new Risk Engine
consumer reads from that queue to compute risk. The roadmap already commits
to RabbitMQ over AMQP, not an AWS-proprietary queue — so the open question
for M2 is who runs the broker, not which one.

As with ADR-001, this is a solo build in a personal AWS account under a
fixed budget, with an established pattern of paying a managed-service
premium when the milestone's real value is elsewhere (Fargate over
self-managed EC2 hosts is the precedent). M2's actual point is the
event-driven boundary and the risk-computation logic behind it, not
operating a message broker.

Self-hosting RabbitMQ on Fargate was seriously considered, and at first
looked cost-comparable to Amazon MQ — around $17-25/month either way, based
on `mq.t3.micro` pricing. That comparison didn't hold up: `mq.t3.micro`
turned out to be deprecated for new brokers, and the real minimum viable
size, `mq.m7g.medium`, costs roughly 4-5x more. So this isn't a cost-neutral
decision. It's a premium paid to avoid three things landing in M2 at once:
AWS Cloud Map for service discovery (the broker has no business being
internet-facing, and this project doesn't have that pattern yet), EFS for
durable storage (Fargate's local disk is ephemeral), and ownership of
RabbitMQ's upgrade path. Speed won out, at a real cost, accepted rather than
glossed over.

## Decision
Milestone 2's broker is Amazon MQ for RabbitMQ: single-instance (no HA), on
`mq.m7g.medium` — the smallest instance type AWS currently allows for a new
RabbitMQ broker. `mq.t3.micro` is deprecated and no longer creatable; AWS
labels `m7g.medium` "Evaluation" tier, which is an honest fit here. It sits
in the private subnets `infra/vpc` already provisions. Credentials are
generated with Terraform's `random_password` and stored in Secrets Manager,
never committed to a `.tf` file or CI variable.

This follows the existing module pattern: a new `infra/messaging` root
module with its own S3 backend key, pulling `vpc_id` and private subnet IDs
from `infra/vpc`'s remote state the same way `infra/ecs` does. It's added to
the `infra.yml` matrix, and `rtrp-ci-permissions` gets a new statement
granting the `mq:*` actions the CI role didn't have.

## Alternatives considered
- **Self-hosted RabbitMQ on ECS Fargate** — not rejected outright, deferred.
  At the corrected cost this is clearly cheaper (~$17-25/month vs.
  `mq.m7g.medium`'s ~$95-125/month), not the cost-neutral option it first
  looked like. Set aside anyway because it bundles three new concerns into
  one milestone — Cloud Map for service discovery, EFS for durable storage,
  owning RabbitMQ's upgrade path — none of which is the actual point of M2.
  The service-discovery piece is useful groundwork for M5's EKS migration (a
  Cloud Map DNS name is conceptually what a Kubernetes `Service` gives you),
  and will likely come up again in M3. Nothing here is lost, just
  resequenced, at a real monthly cost for the delay.
- **Amazon SQS** — rejected. Cheapest, lowest-ops option, needs no new
  Terraform pattern beyond a single `aws_sqs_queue`. But it's
  AWS-proprietary: no exchanges, no routing keys, no AMQP semantics. The
  roadmap already commits to RabbitMQ for this milestone; swapping in SQS
  would mean redesigning the M2 event boundary around a different messaging
  model, not just picking a different host.
- **Amazon MQ, active/standby (HA)** — rejected for M2. Roughly doubles the
  broker cost for a failover guarantee this milestone doesn't need — one
  Trade API instance and one Risk Engine consumer have nothing that depends
  on broker uptime yet. Same logic ADR-001 used to defer EKS: pay for
  resilience once something needs it, not before.

## Consequences
- Ships M2's event boundary faster: no service-discovery setup, no EFS, no
  RabbitMQ upgrade path to own. Effort goes into the message contract and
  the Risk Engine's consumer logic instead — the actual point of this
  milestone.
- Cost: roughly $95-125/month (single-instance `mq.m7g.medium`, estimated
  from AWS's published `mq.m7g.large` rate — verify the exact eu-north-1
  figure against the Pricing Calculator) on top of the ~$60-70/month M1
  already runs, pushing the total toward ~$160-200/month. That's a real
  premium over self-hosting (~$17-25/month). Worth checking against actual
  billing once the broker's been live a month, rather than trusting this
  estimate indefinitely.
- This is the project's first use of Secrets Manager — Amazon MQ requires
  credentials at creation time, and hardcoding them was never on the table.
- `rtrp-ci-permissions` has no `mq:*` actions yet, so the first `terraform
  plan` against `infra/messaging` will fail authorization — same as `ecr`
  and `dns` did when the CI matrix first covered them. Expected this time,
  not a surprise.
- The Cloud Map / service-discovery lesson this choice avoids for M2 isn't
  gone, just deferred. M3's Postgres/Redis, if self-hosted rather than
  RDS/ElastiCache, or a future self-hosted broker migration, would bring it
  back.
- Vendor lock-in is partial: Amazon MQ's control plane is AWS-specific, but
  the data plane speaks standard AMQP, so the Trade API and Risk Engine's
  client code (`pika`) doesn't care who's hosting the broker. Migrating off
  Amazon MQ later means a Terraform and connection-string change, not an
  app rewrite — a smaller switching cost than ADR-001's ECS-to-EKS migration.
