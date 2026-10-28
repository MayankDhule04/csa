# vpc.tf
# ---------------------------------------------------------------------------
# The VPC is the isolated virtual network that contains the entire 3-tier
# application. Configuring the VPC is a CUSTOMER responsibility under the
# Shared Responsibility Model (AWS provides the networking capability; we
# decide the topology, segmentation, and boundaries).
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # DNS support + hostnames are required for RDS endpoints and for instances to
  # resolve names correctly.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
    Tier = "network"
  }
}

# Internet Gateway: the only doorway between the VPC and the public internet.
# It is attached to the VPC but only the PUBLIC route table routes through it,
# so private and isolated subnets have no direct internet path.
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
    Tier = "network"
  }
}
