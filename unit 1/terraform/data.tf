# data.tf
# ---------------------------------------------------------------------------
# Data sources read existing information from AWS at plan time instead of
# hardcoding it. This keeps the project portable across regions and accounts.
# ---------------------------------------------------------------------------

# Availability Zones available in the selected region.
data "aws_availability_zones" "available" {
  state = "available"
}

# The account ID Terraform is running against (used in outputs / documentation).
data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 AMI, resolved dynamically per-region via the public
# SSM Parameter Store path AWS publishes. This avoids hardcoding an AMI ID that
# would break in other regions or become stale over time.
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
