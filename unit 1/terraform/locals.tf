# locals.tf
# ---------------------------------------------------------------------------
# Derived values used across the configuration. Centralising these keeps the
# resource files clean and guarantees the whole project uses one consistent
# naming scheme and subnet layout.
# ---------------------------------------------------------------------------

locals {
  # Standard prefix for every resource name, e.g. "cloudsec-pbl-dev".
  name_prefix = "${var.project_name}-${var.environment}"

  # Availability Zones actually used, sliced from the region's available AZs.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Application port the app tier listens on (behind the load balancer).
  app_port = 80

  # Database port (MySQL).
  db_port = 3306

  # Deterministic, non-overlapping subnet CIDRs derived from the VPC CIDR.
  # newbits = 8 turns a /16 into /24 subnets. The netnum offsets keep each
  # tier in a clearly separate block for readability in the AWS console:
  #   Public (web/LB) : 10.0.0.0/24 , 10.0.1.0/24
  #   App  (private)  : 10.0.10.0/24, 10.0.11.0/24
  #   DB   (isolated) : 10.0.20.0/24, 10.0.21.0/24
  public_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  app_subnet_cidrs    = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  db_subnet_cidrs     = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}
