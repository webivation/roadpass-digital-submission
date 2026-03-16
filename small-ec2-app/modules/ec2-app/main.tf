terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags,
  )
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

# Look up the caller identity so we can build IAM ARNs
data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 AMI – used as a fallback when var.ami_id is empty
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  resolved_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

# ALB security group – accepts HTTP (and optionally HTTPS) from the internet
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Security group for the Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.certificate_arn != "" ? [1] : []
    content {
      description = "HTTPS from internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb-sg" })
}

# EC2 security group – accepts SSH from a management CIDR and HTTP from the ALB
resource "aws_security_group" "ec2" {
  name        = "${local.name_prefix}-ec2-sg"
  description = "Security group for the EC2 instances behind the ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "SSH from management CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-sg" })
}

# ---------------------------------------------------------------------------
# IAM – Instance Role & Profile
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "AllowEC2AssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags               = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-role" })
}

# Manageable policy – add/remove permissions here as requirements grow
data "aws_iam_policy_document" "ec2_policy" {
  # Allow SSM Session Manager (enables shell access without SSH key pair)
  statement {
    sid = "AllowSSMSessionManager"
    actions = [
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
    ]
    resources = ["*"]
  }

  # Allow writing instance logs to CloudWatch
  # `CreateLogGroup` must use "*" as it does not support resource-level permissions.
  statement {
    sid     = "AllowCloudWatchLogsCreateLogGroup"
    actions = [
      "logs:CreateLogGroup",
    ]
    resources = ["*"]
  }

  # Allow log stream creation and publishing logs to specific log groups/streams
  statement {
    sid = "AllowCloudWatchLogsStreamsAndEvents"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:log-group:/roadpass/*:*",
    ]
  }

  # Allow read-only access to S3 project buckets (for pulling configs/assets if needed)
  statement {
    sid = "AllowS3ReadOnly"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.project}-${var.environment}-*",
      "arn:aws:s3:::${var.project}-${var.environment}-*/*",
    ]
  }
}

resource "aws_iam_policy" "ec2" {
  name        = "${local.name_prefix}-ec2-policy"
  description = "Manageable policy for ${local.name_prefix} EC2 instances"
  policy      = data.aws_iam_policy_document.ec2_policy.json
  tags        = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-policy" })
}

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-profile" })
}

# ---------------------------------------------------------------------------
# User-data – JSON payload injected into each instance at launch (fry role)
# ---------------------------------------------------------------------------

locals {
  userdata_json = jsonencode({
    environment  = var.environment
    project      = var.project
    site_title   = var.site_title
    site_heading = var.site_heading
    site_body    = var.site_body
  })
}

# ---------------------------------------------------------------------------
# Launch Template
# ---------------------------------------------------------------------------

resource "aws_launch_template" "this" {
  name_prefix   = "${local.name_prefix}-lt-"
  description   = "Launch template for ${local.name_prefix} nginx instances"
  image_id      = local.resolved_ami_id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  # Attach the instance profile
  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2.arn
  }

  # Attach the EC2 security group
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # EBS root volume
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.root_volume_size_gb
      volume_type           = "gp3"
      delete_on_termination = true
      encrypted             = true
    }
  }

  # User-data: JSON payload consumed by the fry role at boot
  user_data = base64encode(local.userdata_json)

  # Enable detailed monitoring
  monitoring {
    enabled = true
  }

  # Metadata service – enforce IMDSv2
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-ec2" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-ec2-vol" })
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-lt" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alb" })
}

# Target group – instances register here via ASG attachment
resource "aws_lb_target_group" "this" {
  name        = "${local.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP listener – always created; redirects to HTTPS when certificate_arn is set
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.certificate_arn != "" ? [1] : []
    content {
      type = "redirect"
      redirect {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.certificate_arn != "" ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.this.arn
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-http-listener" })
}

# HTTPS listener – only created when a certificate ARN is provided (bonus TLS)
resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-https-listener" })
}

# ---------------------------------------------------------------------------
# Auto Scaling Group
# ---------------------------------------------------------------------------

resource "aws_autoscaling_group" "this" {
  name                = "${local.name_prefix}-asg"
  desired_capacity    = var.asg_desired_capacity
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  vpc_zone_identifier = var.private_subnet_ids

  # Use the launch template
  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Register instances with the ALB target group
  target_group_arns = [aws_lb_target_group.this.arn]

  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Wait for instances to pass ELB health check before marking as InService
  wait_for_elb_capacity = var.asg_desired_capacity

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-ec2"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}
