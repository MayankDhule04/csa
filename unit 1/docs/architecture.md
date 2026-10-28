# Architecture

This document describes the 3-tier web application architecture that the
Terraform code provisions, and the reasoning behind each design decision.

## 1. Goal

Build a realistic but cost-appropriate **3-tier web application** on AWS that
demonstrates core cloud-security concepts:

- **Network segmentation** — each tier lives in its own subnet group.
- **Defense in depth** — multiple independent controls (routing, security
  groups, private placement, IAM, encryption).
- **Least privilege** — every security group allows only the one path it needs.
- **Attack-surface reduction** — only the load balancer is public; the app and
  database are private/isolated.
- **Infrastructure as Code** — the whole stack is reproducible from Terraform.

## 2. The three tiers

| Tier | AWS resource | Subnet type | Internet exposure |
|------|--------------|-------------|-------------------|
| Web / load-balancing | Application Load Balancer | Public | Internet-facing (HTTP 80) |
| Application | EC2 Auto Scaling Group (Amazon Linux 2023 + httpd) | Private | None (no public IP) |
| Database | Amazon RDS for MySQL 8.0 | Isolated | None (no internet route) |

### Web / load-balancing tier
An internet-facing Application Load Balancer (ALB) in the **public** subnets is
the single entry point. It terminates client HTTP connections and forwards them
to the application tier. Clients never connect to app instances or the database
directly.

### Application tier
EC2 instances managed by an **Auto Scaling Group** across two Availability
Zones, in **private** subnets with no public IPs. Each instance runs a minimal
`httpd` site that:
- reports which instance/AZ served the request (proving load balancing + tier
  separation), and
- reads the DB password from SSM at runtime and tests connectivity to RDS
  (proving the app → DB path while the DB stays private).

Administrative access is via **AWS Systems Manager Session Manager**, not SSH,
so there is no inbound SSH port and no key pair to manage or leak.

### Database tier
**Amazon RDS for MySQL** in **isolated** subnets that have no route to the
internet. It is `publicly_accessible = false`, uses a DB subnet group made up
only of the isolated subnets, and accepts connections only from the app-tier
security group on port 3306.

## 3. Networking

- **VPC**: `10.0.0.0/16`.
- **Subnets** (per AZ, 2 AZs by default):
  - Public: `10.0.0.0/24`, `10.0.1.0/24`
  - Private app: `10.0.10.0/24`, `10.0.11.0/24`
  - Isolated DB: `10.0.20.0/24`, `10.0.21.0/24`
- **Internet Gateway**: attached to the VPC; only the public route table uses it.
- **NAT Gateway**: single by default (cost control) in a public subnet; gives
  the private app tier **outbound-only** internet for OS patching, package
  installs, and AWS API calls.
- **Route tables**:
  - Public → `0.0.0.0/0` via IGW.
  - App → `0.0.0.0/0` via NAT GW (outbound only).
  - DB → local only (**no** default route — fully isolated).

## 4. High availability

- Subnets and the ALB span **two Availability Zones**.
- The app tier ASG places instances in both AZs.
- RDS Multi-AZ is available via `db_multi_az` (off by default to control cost;
  turning it on adds a standby in the second AZ).

This gives a genuinely multi-AZ design without provisioning expensive resources
purely for appearance.

## 5. Key design decisions (and why)

| Decision | Rationale |
|----------|-----------|
| ALB instead of a public EC2 web server | Provides a clean public/private split and a single, hardenable entry point. |
| Auto Scaling Group instead of a single EC2 | Demonstrates HA and self-healing; instances spread across AZs. |
| Single NAT Gateway by default | NAT is the main billable networking item; one is enough for a demo. Toggle `single_nat_gateway = false` for per-AZ resilience. |
| RDS MySQL `db.t3.micro`, single-AZ default | Managed database that shows the shared-responsibility split; small class keeps it free-tier friendly. |
| HTTP (80) on the listener, not HTTPS | Avoids requiring a domain + ACM certificate for a student demo. Production guidance to use HTTPS is documented in `security-design.md`. |
| SSM Session Manager instead of SSH | Removes the SSH attack surface; access is IAM-controlled and audited. |
| DB password via `random_password` → SSM SecureString | No secret is ever written into code or Git; the app reads it at runtime via a least-privilege IAM role. |
| IMDSv2 enforced | Mitigates SSRF-based theft of instance credentials. |
| Encryption at rest on EBS and RDS | Protects data at rest; a customer-configurable control. |

See `security-design.md` for the full security rationale and
`shared-responsibility-matrix.md` for the responsibility breakdown.
