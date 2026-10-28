# subnets.tf
# ---------------------------------------------------------------------------
# Three subnet groups, one per tier, spread across multiple Availability Zones.
# This is the core of NETWORK SEGMENTATION and DEFENSE IN DEPTH:
#
#   * Public subnets  -> web / load-balancing tier (internet-reachable)
#   * App subnets     -> application tier (private, no public IP)
#   * DB subnets      -> database tier (isolated, no route to internet at all)
#
# Splitting across AZs provides HIGH AVAILABILITY without adding real cost for
# the subnets themselves.
# ---------------------------------------------------------------------------

# ------------------------- Public subnets (Web/LB tier) --------------------
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true # resources here (e.g. NAT GW) get public IPs

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public-web"
  }
}

# ------------------------- Private subnets (App tier) ----------------------
resource "aws_subnet" "app" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.app_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # app instances never get public IPs

  tags = {
    Name = "${local.name_prefix}-app-${local.azs[count.index]}"
    Tier = "private-app"
  }
}

# ------------------------- Isolated subnets (DB tier) ----------------------
resource "aws_subnet" "db" {
  count = var.az_count

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.db_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false # database is never publicly addressable

  tags = {
    Name = "${local.name_prefix}-db-${local.azs[count.index]}"
    Tier = "isolated-db"
  }
}

# ------------------------- RDS DB subnet group -----------------------------
# RDS requires a subnet group spanning >= 2 AZs. We give it ONLY the isolated
# DB subnets, guaranteeing the database can never be placed in a subnet that
# has an internet route.
resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
    Tier = "isolated-db"
  }
}
