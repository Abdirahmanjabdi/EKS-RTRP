# 1. Target Group (Target type IP for Fargate)
resource "aws_lb_target_group" "trade_api" {
  name        = "${var.project_name}-trade-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = "ip"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${var.project_name}-trade-api-tg" }
}

# 2. Application Load Balancer (Spanning public subnets)
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.terraform_remote_state.vpc.outputs.public_subnet_ids

  tags = { Name = "${var.project_name}-alb" }
}

# 3. ALB Listener on Port 80 forwarding to Target Group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.trade_api.arn
  }
}