resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-cache-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "redis" {
  name        = "${var.project_name}-redis-sg"
  description = "Allow Redis/Valkey from Trade API and Risk Engine tasks only"
  vpc_id      = var.vpc_id

    ingress {
    description = "Valkey from ECS tasks"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    security_groups = [
      var.ecs_tasks_security_group_id,
      var.risk_engine_security_group_id,
      var.ml_inference_security_group_id,
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-redis-sg" }
}

# AUTH token — generated the same way messaging's broker credentials were.
# ElastiCache requires 16-128 chars; disallowed special characters make
# alphanumeric-only the simplest safe choice, same reasoning as messaging.
resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name = "${var.project_name}-redis-auth-token"
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = random_password.redis_auth.result
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.project_name}-redis"
  description           = "Single-node cache for computed risk exposure"

  engine             = "valkey"
  engine_version     = var.engine_version
  node_type          = "cache.t4g.micro"
  num_cache_clusters = 1

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}