resource "aws_iam_role" "role" {
  name = "${var.env}-${var.component}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-${var.component}-role" }
  )
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.env}-${var.component}-role"
  role = aws_iam_role.role.name
}

resource "aws_iam_policy" "policy" {
  name        = "${var.env}-${var.component}-parameter-store-policy"
  path        = "/"
  description = "${var.env}-${var.component}-parameter-store-policy"


  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameterHistory",
          "ssm:GetParametersByPath",
          "ssm:GetParameters",
          "ssm:GetParameter"
        ],
        "Resource": [
        "arn:aws:ssm:us-east-1:553708275319:parameter/${var.env}.${var.component}*",
        "arn:aws:ssm:us-east-1:553708275319:parameter/nexus*",
        "arn:aws:ssm:us-east-1:553708275319:parameter/${var.env}.docdb*",
        "arn:aws:ssm:us-east-1:553708275319:parameter/${var.env}.elasticache*",
        "arn:aws:ssm:us-east-1:553708275319:parameter/${var.env}.rds*",
        "arn:aws:ssm:us-east-1:553708275319:parameter/${var.env}.rabbitmq*",
        "arn:aws:ssm:us-east-1:633788536644:parameter/grafana*",
        "arn:aws:ssm:us-east-1:633788536644:parameter/${var.env}.ssh*"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "ssm:DescribeParameters",
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "role-attach" {
  role       = aws_iam_role.role.name
  policy_arn = aws_iam_policy.policy.arn
}

resource "aws_security_group" "main" {
  name        = "${var.env}-${var.component}-security-group"
  description = "${var.env}-${var.component}-security-group"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = var.allow_cidr
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_cidr
  }

  ingress {
    description = "PROMETHEUS"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = var.monitor_cidr
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    { Name = "${var.env}-${var.component}-security-group" }
  )
}


resource "aws_launch_template" "main" {
  name                   = "${var.env}-${var.component}-template"
  image_id               = data.aws_ami.centos8.id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.main.id]
  user_data              = base64encode(templatefile("${path.module}/user-data.sh", { component = var.component, env = var.env }))
  iam_instance_profile {
    arn = aws_iam_instance_profile.profile.arn
  }
  instance_market_options {
    market_type = "spot"
  }
}

resource "aws_autoscaling_group" "asg" {
  name                = "${var.env}-${var.component}-asg"
  max_size            = var.max_size
  min_size            = var.min_size
  desired_capacity    = var.desired_capacity
  force_delete        = true
  vpc_zone_identifier = var.subnet_ids
  target_group_arns   = [aws_lb_target_group.target_group.arn]

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = local.all_tags
    content {
      key                 = tag.value.key
      value               = tag.value.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_policy" "cpu-tracking-policy" {
  name        = "whenCPULoadIncrease"
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 30.0
  }
  autoscaling_group_name = aws_autoscaling_group.asg.name
}


resource "aws_route53_record" "app" {
  zone_id = "Z10181653L4NCOVM5PP96"
  name    = "${var.component}-${var.env}.lokeshviswa44.online"
  type    = "CNAME"
  ttl     = 30
  records = [var.alb]
}

resource "aws_lb_target_group" "target_group" {
  name     = "${var.component}-${var.env}"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 5
    path                = "/health"
    protocol            = "HTTP"
    timeout             = 2
  }
  deregistration_delay = 10
}

// THis is for backend components
resource "aws_lb_listener_rule" "backend_rule" {
  count        = var.listener_priority != 0 ? 1 : 0
  listener_arn = var.listener
  priority     = var.listener_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }

  condition {
    host_header {
      values = ["${var.component}-${var.env}.lokeshviswa44.online"]
    }
  }
}

// This is only for frontend
resource "aws_lb_listener" "frontend" {
  count             = var.listener_priority == 0 ? 1 : 0
  load_balancer_arn = var.alb_arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:us-east-1:633788536644:certificate/e0de402e-a390-4600-a292-bf3b5b926201"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn
  }
}


resource "aws_lb_listener" "frontend_http" {
  count             = var.listener_priority == 0 ? 1 : 0
  load_balancer_arn = var.alb_arn
  port              = "80"
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