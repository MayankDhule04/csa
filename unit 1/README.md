# Cloud Security PBL — Unit 1

**Option 1 — Responsibility Mapping & Asset Definition**

A complete, GitHub-ready academic project that designs and **actually builds** a
secure AWS **3-tier web application** using **Terraform**, and maps every
security control to the **AWS Shared Responsibility Model**.

---

## Table of contents

1. [Project Overview](#1-project-overview)
2. [Assignment Objective](#2-assignment-objective)
3. [Architecture](#3-architecture)
4. [Architecture Diagram](#4-architecture-diagram)
5. [AWS Services Used](#5-aws-services-used)
6. [Network Architecture](#6-network-architecture)
7. [Security Architecture](#7-security-architecture)
8. [Traffic Flow](#8-traffic-flow)
9. [Security Group Design](#9-security-group-design)
10. [Shared Responsibility Matrix](#10-shared-responsibility-matrix)
11. [Terraform Structure](#11-terraform-structure)
12. [Prerequisites](#12-prerequisites)
13. [AWS Configuration](#13-aws-configuration)
14. [Terraform Deployment](#14-terraform-deployment)
15. [Terraform Validation](#15-terraform-validation)
16. [Verification](#16-verification)
17. [Screenshots / Evidence](#17-screenshots--evidence)
18. [Cost Considerations](#18-cost-considerations)
19. [Security Considerations](#19-security-considerations)
20. [Cleanup / Destroy](#20-cleanup--destroy)
21. [Conclusion](#21-conclusion)

---

## 1. Project Overview

This project provisions a realistic **3-tier web application** on AWS entirely
through **Infrastructure as Code (Terraform)**. The three tiers — a public
web/load-balancing tier, a private application tier, and an isolated database
tier — are deliberately segmented so the project can **demonstrate cloud
security concepts** rather than just host a website.

It shows, with working infrastructure, how responsibilities are divided between
AWS and the customer, and how principles such as **defense in depth**,
**network segmentation**, **least privilege**, and **attack-surface reduction**
are applied in practice.

## 2. Assignment Objective

Unit 1 offers a choice; this submission covers **Option 1 — Responsibility
Mapping & Asset Definition**, which requires:

1. Designing the architecture of a **3-tier web application** (web, app, DB).
2. Creating a **Shared Responsibility Matrix** tailored to this application.
3. Documenting which security controls are the **customer's** responsibility and
   which are **AWS's**.

Plus the submission requirement to **actually build it with Terraform**, capture
**screenshots as evidence**, and publish the **code + documentation to GitHub**.

## 3. Architecture

| Tier | AWS resource | Placement | Public? |
|------|--------------|-----------|:-------:|
| Web / load balancing | Application Load Balancer (ALB) | Public subnets (2 AZs) | Yes (HTTP 80) |
| Application | EC2 Auto Scaling Group — Amazon Linux 2023 + `httpd` | Private subnets (2 AZs) | No |
| Database | Amazon RDS for MySQL 8.0 | Isolated subnets (2 AZs) | No |

The app tier reaches the internet **outbound only** through a NAT Gateway (for
patching and AWS API calls). The database has **no internet route at all**. Full
reasoning is in [`docs/architecture.md`](docs/architecture.md).

## 4. Architecture Diagram

A full ASCII + Mermaid diagram that matches the Terraform exactly lives in
[`architecture-diagram/architecture.md`](architecture-diagram/architecture.md).
Condensed view:

```
Internet
   │ HTTP 80
   ▼
Internet Gateway
   │
   ▼
[ PUBLIC subnets ]   Application Load Balancer  (SG: alb-sg :80)
   │ 80  (SG reference alb-sg ➜ app-sg)
   ▼
[ PRIVATE subnets ]  EC2 Auto Scaling Group      (SG: app-sg :80)
   │ 3306 (SG reference app-sg ➜ db-sg)
   ▼
[ ISOLATED subnets ] Amazon RDS MySQL            (SG: db-sg :3306, no public route)
```

## 5. AWS Services Used

| Service | Role in this project |
|---------|----------------------|
| Amazon VPC | Isolated virtual network (`10.0.0.0/16`) |
| Subnets (public/private/isolated) | Network segmentation across 2 AZs |
| Internet Gateway | Inbound/outbound path for the public tier |
| NAT Gateway + Elastic IP | Outbound-only internet for the private app tier |
| Route Tables | Enforce which tiers can reach the internet |
| Security Groups | Stateful least-privilege firewalls per tier |
| Application Load Balancer | Public web tier / single entry point |
| EC2 + Launch Template + Auto Scaling Group | Application tier (HA across AZs) |
| Amazon RDS for MySQL | Managed, private database tier |
| IAM (role + instance profile) | Least-privilege access for app instances |
| AWS Systems Manager (Session Manager + Parameter Store) | Keyless admin access + encrypted secret storage |
| KMS | Encryption of RDS storage, EBS, and the SecureString secret |

## 6. Network Architecture

- **VPC:** `10.0.0.0/16`, DNS support + hostnames enabled.
- **Public subnets:** `10.0.0.0/24`, `10.0.1.0/24` — ALB and NAT Gateway.
- **Private app subnets:** `10.0.10.0/24`, `10.0.11.0/24` — EC2 app tier.
- **Isolated DB subnets:** `10.0.20.0/24`, `10.0.21.0/24` — RDS + DB subnet group.
- **Routing:**
  - Public → `0.0.0.0/0` via Internet Gateway.
  - App → `0.0.0.0/0` via NAT Gateway (**outbound only**).
  - DB → **local only** (no internet route).

Details: [`docs/architecture.md`](docs/architecture.md).

## 7. Security Architecture

Security is the primary purpose of this project. Controls include:

- **Network segmentation** — three separate subnet groups, each with its own
  route table.
- **Defense in depth** — routing *and* security groups must both permit a flow;
  the DB is protected by both an isolated route table and an SG that only trusts
  the app tier.
- **Least privilege** — SGs allow exactly one required path each, using
  security-group references instead of broad CIDRs.
- **Attack-surface reduction** — only the ALB is public; app instances have no
  public IP; the DB has no internet route; **no SSH** (SSM Session Manager only);
  **IMDSv2 required**.
- **Secrets management** — DB password generated by Terraform, stored in SSM
  SecureString, read at runtime via a least-privilege IAM role — never in code.
- **Encryption at rest** — RDS storage and EC2 EBS volumes encrypted.

Full rationale: [`docs/security-design.md`](docs/security-design.md).

## 8. Traffic Flow

**Request path (inbound):**
```
Client → Internet Gateway → ALB (:80, public) → EC2 app (:80, private) → RDS (:3306, isolated) → response back up the path
```

**Maintenance path (outbound only):**
```
EC2 app → NAT Gateway → Internet Gateway → Internet   (OS updates, package repos, AWS APIs)
RDS     → (no internet route — cannot reach or be reached by the internet)
```

## 9. Security Group Design

| SG | Ingress | Egress | Intent |
|----|---------|--------|--------|
| `alb-sg` (web) | TCP 80 from `allowed_web_cidr` (default `0.0.0.0/0`) | TCP 80 → `app-sg` | Only HTTP in from clients; forward only to app tier |
| `app-sg` (app) | TCP 80 from `alb-sg` | TCP 3306 → `db-sg`; TCP 443/80 → internet (via NAT) | Reachable only via ALB; talk to DB + patch outbound |
| `db-sg` (db) | TCP 3306 from `app-sg` | none | MySQL only from app tier; no public exposure |

Inter-tier rules use **security-group references**, not CIDRs, so they remain
correct regardless of IP layout. See
[`docs/security-design.md`](docs/security-design.md).

## 10. Shared Responsibility Matrix

A detailed matrix tailored to this architecture — covering physical security,
hardware, networking, VPC, security groups, IAM, OS patching, application,
database, encryption, secrets, logging, monitoring, backups, access control,
vulnerability management, data protection, and incident response — is in
[`docs/shared-responsibility-matrix.md`](docs/shared-responsibility-matrix.md).

**In one line:** AWS secures the *facilities, hardware, hypervisor, managed RDS
engine, and service availability*; I secure the *VPC design, segmentation,
security groups, IAM, OS/app, encryption enablement, secrets, and monitoring* —
with several domains **shared** along a clearly defined boundary.

## 11. Terraform Structure

```
unit-1/
├── terraform/
│   ├── versions.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── data.tf
│   ├── vpc.tf
│   ├── subnets.tf
│   ├── routes.tf
│   ├── security_groups.tf
│   ├── load_balancer.tf
│   ├── application.tf
│   ├── database.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── templates/
│   │   └── user_data.sh.tpl
│   └── README.md
├── docs/
│   ├── architecture.md
│   ├── shared-responsibility-matrix.md
│   └── security-design.md
├── architecture-diagram/
│   └── architecture.md
├── screenshots/
│   └── README.md
├── README.md
└── .gitignore
```

## 12. Prerequisites

- **Terraform** >= 1.5 ([install](https://developer.hashicorp.com/terraform/install))
- **AWS CLI** v2 ([install](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))
- An **AWS account** and an IAM identity allowed to create VPC, EC2, ELB, RDS,
  IAM, SSM, and KMS resources.
- A region with capacity for the default instance types (default `us-east-1`).

## 13. AWS Configuration

Authentication uses **AWS IAM Identity Center (SSO)**, which is the recommended
modern workflow: it issues **short-lived, automatically-rotated credentials**
instead of long-lived access keys, so no static secret ever lands on disk or in
the repo.

**Recommended — IAM Identity Center / SSO:**

```powershell
# One-time interactive setup (opens a browser to sign in and pick an account/role)
aws configure sso
#   SSO start URL : https://<your-org>.awsapps.com/start
#   SSO region    : <your-identity-center-region>
#   Account/role  : choose the account + permission set to deploy with
#   CLI profile   : e.g. cloudsec-pbl

# Sign in for the session (re-run when the session token expires)
aws sso login --profile cloudsec-pbl

# Point Terraform + CLI at that profile (or add profile = "cloudsec-pbl" to provider.tf)
$env:AWS_PROFILE = "cloudsec-pbl"

aws sts get-caller-identity   # confirm the identity/account/region
```

Terraform reads this profile automatically via the standard AWS credential
chain (`AWS_PROFILE` → `~/.aws/config`) — no keys are written into any `.tf`
file. The SSO cache lives under `~/.aws/sso`, which `.gitignore` excludes.

**Alternative — static IAM user access keys** (only if SSO is unavailable):

```powershell
aws configure                 # stores keys in ~/.aws/credentials (never commit)
aws sts get-caller-identity
```

If you use static keys, rotate them regularly and prefer SSO where possible —
this is a customer responsibility under the Shared Responsibility Model.

## 14. Terraform Deployment

```powershell
cd terraform
Copy-Item terraform.tfvars.example terraform.tfvars   # optional; edit values
terraform init
terraform plan
terraform apply           # confirm with "yes"
terraform output alb_url  # open this URL in a browser
```

Allow ~2–4 minutes after apply for instances to install `httpd` and pass ALB
health checks.

## 15. Terraform Validation

No AWS account is needed just to validate syntax and structure:

```powershell
cd terraform
terraform init -backend=false
terraform fmt -check
terraform validate
```

Expected result: `Success! The configuration is valid.`

## 16. Verification

After `terraform apply`, verify the architecture and security posture:

| Check | How | Expected |
|-------|-----|----------|
| VPC exists | AWS Console → VPC | `cloudsec-pbl-dev-vpc` (10.0.0.0/16) |
| Subnets correct | VPC → Subnets | 2 public, 2 app, 2 db across 2 AZs |
| Routing correct | VPC → Route tables | Public→IGW, app→NAT, db→local only |
| SGs correct | EC2 → Security Groups | app from alb only; db 3306 from app only |
| Web tier reachable | Browser → `alb_url` | Demo page loads |
| App not public | EC2 → Instances | App instances have **no public IPv4** |
| DB not public | RDS → database | **Publicly accessible = No** |
| DB reachable only from app | Demo page | "Database connectivity: CONNECTED" |
| DB blocked from internet | `Test-NetConnection <rds-endpoint> -Port 3306` from your laptop | Times out / fails |

```powershell
# from your laptop – should FAIL/timeout, proving the DB is private
Test-NetConnection (terraform output -raw db_endpoint).Split(":")[0] -Port 3306
```

## 17. Screenshots / Evidence

A complete, numbered screenshot checklist — with what must be visible, why it is
evidence, and which requirement it proves — is in
[`screenshots/README.md`](screenshots/README.md). Capture these **after**
deployment and place the images in `screenshots/`.

> Screenshots are intentionally **not** included yet — they must be captured
> from a real deployment. Do not fabricate them.

## 18. Cost Considerations

This is a student project; keep it running only while demonstrating, then
destroy it.

| Resource | Charge type | Note |
|----------|-------------|------|
| NAT Gateway + EIP | Hourly + data | **Main cost.** Single NAT by default. |
| Application Load Balancer | Hourly + LCU | Runs while deployed. |
| EC2 (2 × t3.micro) | Hourly | Free-tier friendly in many regions. |
| RDS (db.t3.micro, single-AZ) | Hourly + storage | Free-tier friendly in many regions. |
| Data transfer | Usage | Minimal for a demo. |

Cost-control levers: `single_nat_gateway = true` (default), `db_multi_az = false`
(default), small instance classes, and running `terraform destroy` when done.

## 19. Security Considerations

Implemented: network segmentation, least-privilege security groups (SG
references), private app tier, isolated/private database, IMDSv2, no SSH (SSM
only), encryption at rest (RDS + EBS), secrets in SSM SecureString, least-
privilege IAM, ALB invalid-header dropping, multi-AZ + Auto Scaling.

**Honest limitations (no overstated claims):**
- The ALB listener is **HTTP (80)**, not HTTPS — intentional, to avoid a
  domain/ACM requirement for a student demo. Production should use HTTPS:443 +
  ACM with an HTTP→HTTPS redirect.
- Logging/monitoring services (CloudTrail, VPC Flow Logs, GuardDuty, ALB access
  logs) are described in the docs but not enabled by default, to control cost.
- Terraform state is local by default and may contain sensitive values — it is
  git-ignored; a remote encrypted backend is recommended for teams.

See [`docs/security-design.md`](docs/security-design.md) for full detail.

## 20. Cleanup / Destroy

```powershell
cd terraform
terraform destroy   # confirm with "yes"
```

This removes every billable resource. Confirm in the console that the ALB, NAT
Gateway, EC2 instances, and RDS instance are gone.

## 21. Conclusion

This project demonstrates a working, security-focused **3-tier AWS architecture**
built entirely with **Terraform**. It applies **defense in depth**, **network
segmentation**, **least privilege**, and **attack-surface reduction**, keeps the
**database private**, manages **secrets** without committing them, and documents
a **Shared Responsibility Matrix** specific to the deployed resources. The
Terraform code, architecture diagram, security design, and responsibility matrix
all describe the **same** architecture, providing an internally consistent,
academically presentable Cloud Security PBL submission.

---

### Repository documentation map
- [`terraform/README.md`](terraform/README.md) — how to run the Terraform
- [`docs/architecture.md`](docs/architecture.md) — architecture & decisions
- [`docs/security-design.md`](docs/security-design.md) — security controls
- [`docs/shared-responsibility-matrix.md`](docs/shared-responsibility-matrix.md) — responsibility mapping
- [`architecture-diagram/architecture.md`](architecture-diagram/architecture.md) — diagram
- [`screenshots/README.md`](screenshots/README.md) — evidence checklist
