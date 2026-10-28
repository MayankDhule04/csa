# security_groups.tf
# ---------------------------------------------------------------------------
# Security Groups are stateful virtual firewalls attached to each tier. They
# are the primary demonstration of LEAST PRIVILEGE in this project.
#
# Traffic is allowed ONLY along the intended path:
#
#   Internet --(HTTP 80)--> ALB SG --(80)--> App SG --(3306)--> DB SG
#
# Wherever one tier talks to another we reference the SOURCE SECURITY GROUP,
# not a CIDR range. This means "any instance in the app tier" rather than "any
# IP in this subnet range", so the rule stays correct even if subnets change.
#
# Rules are defined as standalone aws_vpc_security_group_*_rule resources
# (not inline) to avoid dependency cycles between mutually-referencing groups
# and to keep each rule individually documented and auditable.
# ---------------------------------------------------------------------------

# =========================== ALB / Web tier SG =============================
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Public load balancer: allow inbound HTTP from the internet only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-alb-sg"
    Tier = "public-web"
  }
}

# Inbound: HTTP from the allowed web CIDR (default: entire internet).
resource "aws_vpc_security_group_ingress_rule" "alb_http_in" {
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from clients"
  cidr_ipv4         = var.allowed_web_cidr
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# Outbound: only forward to the app tier on the application port. The ALB does
# not need to reach anything else.
resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Forward traffic to the application tier"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = local.app_port
  to_port                      = local.app_port
  ip_protocol                  = "tcp"
}

# =========================== Application tier SG ===========================
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "App tier: accept traffic only from the load balancer"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-app-sg"
    Tier = "private-app"
  }
}

# Inbound: application port, ONLY from the ALB security group (SG reference).
resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "Allow app traffic only from the load balancer"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = local.app_port
  to_port                      = local.app_port
  ip_protocol                  = "tcp"
}

# Outbound: to the database tier on the MySQL port (SG reference).
resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "Allow app tier to reach the database tier"
  referenced_security_group_id = aws_security_group.db.id
  from_port                    = local.db_port
  to_port                      = local.db_port
  ip_protocol                  = "tcp"
}

# Outbound: HTTPS to the internet (via NAT) for OS/security updates and to
# reach AWS APIs (SSM, package repos). Scoped to 443 to keep egress tight.
resource "aws_vpc_security_group_egress_rule" "app_https_out" {
  security_group_id = aws_security_group.app.id
  description       = "Allow HTTPS egress for patching/updates via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# Outbound: HTTP to the internet (via NAT) for package repositories that still
# serve some metadata/mirrors over HTTP.
resource "aws_vpc_security_group_egress_rule" "app_http_out" {
  security_group_id = aws_security_group.app.id
  description       = "Allow HTTP egress for package repositories via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

# =========================== Database tier SG ==============================
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "DB tier: accept MySQL only from the application tier"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-db-sg"
    Tier = "isolated-db"
  }
}

# Inbound: MySQL (3306) ONLY from the app tier SG. There is deliberately NO
# rule allowing the internet or any wider CIDR, so the database cannot be
# reached publicly.
resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "Allow MySQL only from the application tier"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = local.db_port
  to_port                      = local.db_port
  ip_protocol                  = "tcp"
}

# The DB SG has NO egress rules defined here. With standalone egress rules,
# omitting them means the group has no egress allowances beyond what RDS needs
# internally, further shrinking the attack surface. (RDS management traffic is
# handled by AWS on the service side.)
