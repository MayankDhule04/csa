# routes.tf
# ---------------------------------------------------------------------------
# Route tables enforce which subnets can reach the internet and how.
#
#   * Public route table  -> 0.0.0.0/0 via Internet Gateway   (inbound+outbound)
#   * App route table(s)  -> 0.0.0.0/0 via NAT Gateway         (outbound only)
#   * DB route table      -> NO 0.0.0.0/0 route at all         (fully isolated)
#
# The NAT Gateway lets private app instances pull OS/security updates and
# reach AWS APIs WITHOUT being reachable from the internet. The database has
# no default route, so it is unreachable from and cannot initiate traffic to
# the internet - reducing the attack surface to the maximum.
# ---------------------------------------------------------------------------

# ----------------------------- Public routing -----------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
    Tier = "public-web"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ----------------------------- NAT Gateway ---------------------------------
# One NAT GW by default (single_nat_gateway = true) to control cost; optionally
# one per AZ for full resilience. NAT Gateways and their Elastic IPs DO incur
# hourly + data charges - this is the main billable networking component.
locals {
  nat_gateway_count = var.single_nat_gateway ? 1 : var.az_count
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index}"
    Tier = "network"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  # NAT Gateways live in PUBLIC subnets (they need an internet path).
  subnet_id = aws_subnet.public[count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-${count.index}"
    Tier = "network"
  }

  depends_on = [aws_internet_gateway.main]
}

# --------------------------- Private app routing ---------------------------
# One route table per AZ so each AZ can use its local NAT GW when
# single_nat_gateway = false; when true, all point at the single NAT GW.
resource "aws_route_table" "app" {
  count  = var.az_count
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[var.single_nat_gateway ? 0 : count.index].id
  }

  tags = {
    Name = "${local.name_prefix}-app-rt-${local.azs[count.index]}"
    Tier = "private-app"
  }
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# --------------------------- Isolated DB routing ---------------------------
# Deliberately has NO route to an Internet Gateway or NAT Gateway. The only
# implicit route is "local" (intra-VPC), so the DB tier can talk to the app
# tier and nothing else can be reached from it.
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-rt"
    Tier = "isolated-db"
  }
}

resource "aws_route_table_association" "db" {
  count          = var.az_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
