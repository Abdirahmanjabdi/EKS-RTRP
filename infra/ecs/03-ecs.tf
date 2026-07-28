# 1. CloudWatch Log Group for ECS Container Logging
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}-trade-api"
  retention_in_days = 7
}

# 2. IAM Task Execution Role (Pulls from ECR, writes logs to CloudWatch)
resource "aws_iam_role" "execution" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 3. IAM Task Role (Placeholder for M2+ AWS API integrations)
resource "aws_iam_role" "task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# 4. ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# 5. ECS Task Definition
resource "aws_ecs_task_definition" "trade_api" {
  family                   = "${var.project_name}-trade-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "trade-api"
    image     = "026703081738.dkr.ecr.eu-north-1.amazonaws.com/rtrp-trade-api:v0"
    essential = true
    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "trade-api"
      }
    }
  }])
}

# 6. ECS Service (Running inside private subnets, linked to ALB target group)
resource "aws_ecs_service" "trade_api" {
  name            = "${var.project_name}-trade-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.trade_api.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.vpc.outputs.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.trade_api.arn
    container_name   = "trade-api"
    container_port   = 8000
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.execution
  ]
}