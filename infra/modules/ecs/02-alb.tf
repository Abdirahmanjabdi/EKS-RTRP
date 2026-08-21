# 1. Target Group (Target type IP for Fargate)
resource "aws_lb_target_group" "trade_api" {
  name        = "${var.project_name}-trade-api-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
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
  subnets            = var.public_subnet_ids

  tags = { Name = "${var.project_name}-alb" }
}



# 1. Port 80 Listener: Forces a redirect to HTTPS (Port 443)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
    }
  }
}

# 2. Port 443 Listener: Terminates TLS using our ACM certificate and forwards to the target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = "arn:aws:acm:eu-north-1:026703081738:certificate/5fa4994c-2cad-408b-bf38-c6f20a406ec3"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.trade_api.arn
  }
}
