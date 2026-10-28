# application.tf
# ---------------------------------------------------------------------------
# The application tier: EC2 instances in the PRIVATE app subnets, managed by an
# Auto Scaling Group and registered behind the ALB target group.
#
# Security design choices:
#   * NO SSH key pair and NO inbound SSH. Administrative access is via AWS
#     Systems Manager Session Manager (IAM-controlled, audited), which removes
#     the SSH attack surface entirely.
#   * Instances have NO public IP and sit in private subnets.
#   * IMDSv2 is enforced on the launch template to mitigate SSRF-based
#     credential theft from the instance metadata service.
#   * The instance IAM role is least-privilege: SSM access + read-only on the
#     single SSM parameter that holds the DB password.
# ---------------------------------------------------------------------------

# --------------------------- IAM for EC2 (SSM) -----------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${local.name_prefix}-app-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${local.name_prefix}-app-role"
    Tier = "private-app"
  }
}

# Managed policy that enables Session Manager (no SSH needed).
resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Least-privilege inline policy: read ONLY the DB password parameter and decrypt
# it with the specific SSM-managed KMS key (scoped, not "*"), and only when the
# request is routed through SSM. This is how the app obtains the secret at
# runtime instead of having it baked into code or user-data.
data "aws_iam_policy_document" "app_secrets" {
  statement {
    sid       = "ReadDbPasswordParam"
    actions   = ["ssm:GetParameter", "ssm:GetParameters"]
    resources = [aws_ssm_parameter.db_password.arn]
  }
  statement {
    sid     = "DecryptDbPassword"
    actions = ["kms:Decrypt"]

    # The resource stays "*" because it targets the AWS-managed SSM key
    # (alias/aws/ssm), whose key ARN cannot be computed without a KMS read
    # permission the deployer may not have. Instead of a broad grant, the two
    # conditions below make this permission effectively "decrypt ONLY this one
    # parameter's value, and ONLY when the request comes through SSM":
    #   1. kms:ViaService        -> the call must be made by SSM in this region,
    #                               not a direct KMS Decrypt call.
    #   2. EncryptionContext     -> SSM tags SecureString decryptions with the
    #                               parameter ARN; this pins decrypt to exactly
    #                               the DB password parameter, no other secret.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:PARAMETER_ARN"
      values   = [aws_ssm_parameter.db_password.arn]
    }
  }
}

resource "aws_iam_role_policy" "app_secrets" {
  name   = "${local.name_prefix}-app-read-db-secret"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app_secrets.json
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

# ------------------------------ Launch template ----------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.app_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [aws_security_group.app.id]

  # Enforce IMDSv2 (token-required) to reduce SSRF credential-theft risk.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Encrypt the root EBS volume at rest.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    db_host       = aws_db_instance.main.address
    db_port       = local.db_port
    db_name       = var.db_name
    db_user       = var.db_username
    db_pw_ssm     = aws_ssm_parameter.db_password.name
    aws_region    = var.aws_region
    project_title = "Cloud Security PBL - Unit 1"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${local.name_prefix}-app"
      Tier = "private-app"
    }
  }

  tags = {
    Name = "${local.name_prefix}-app-lt"
    Tier = "private-app"
  }
}

# ------------------------------ Auto Scaling Group --------------------------
resource "aws_autoscaling_group" "app" {
  name                = "${local.name_prefix}-app-asg"
  desired_capacity    = var.app_desired_capacity
  min_size            = var.app_min_size
  max_size            = var.app_max_size
  vpc_zone_identifier = aws_subnet.app[*].id
  target_group_arns   = [aws_lb_target_group.app.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # Propagate a Name tag to launched instances.
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Tier"
    value               = "private-app"
    propagate_at_launch = true
  }

  # Wait for instances to pass ELB health checks before considering the ASG
  # created, so the demo is reachable right after apply.
  wait_for_capacity_timeout = "10m"
}
