# load_balancer.tf
# ---------------------------------------------------------------------------
# The Application Load Balancer (ALB) is the internet-facing entry point and
# the "web tier" of the architecture. It lives in the PUBLIC subnets and is the
# ONLY component exposed to the internet. All client traffic terminates here
# and is forwarded to the private application tier - clients never talk to the
# app instances or the database directly.
# ---------------------------------------------------------------------------

resource "aws_lb" "web" {
  name               = "${local.name_prefix}-alb"
  internal           = false # internet-facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # Drop invalid/malformed HTTP headers - a small attack-surface reduction.
  drop_invalid_header_fields = true

  # Kept false so `terraform destroy` works cleanly for a student project.
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
    Tier = "public-web"
  }
}

# Target group for the application-tier instances registered by the ASG.
resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = local.app_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  # Health check confirms each app instance is serving before the ALB sends it
  # traffic - part of making the demo reliably reachable.
  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name_prefix}-app-tg"
    Tier = "public-web"
  }
}

# HTTP listener on port 80 forwards to the app target group.
# NOTE: HTTP (not HTTPS) is used intentionally to keep the student demo free of
# ACM certificate / domain requirements. In production this listener would be
# HTTPS (443) with a redirect from 80 - see docs/security-design.md.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = {
    Name = "${local.name_prefix}-http-listener"
    Tier = "public-web"
  }
}
