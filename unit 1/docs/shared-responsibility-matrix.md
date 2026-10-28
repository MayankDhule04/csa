# Shared Responsibility Matrix

This matrix is tailored to **this specific architecture** — an AWS 3-tier web
application (ALB → EC2 Auto Scaling app tier → RDS MySQL) built with Terraform.
It maps each security domain to the responsible party and explains **why**,
referencing the actual resources in this project.

Legend:
- **AWS** — AWS is responsible (part of "security *of* the cloud").
- **Customer** — I (the student/customer) am responsible (part of "security
  *in* the cloud").
- **Shared** — both parties own a portion; the boundary is explained.

AWS's model is often summarised as: **AWS secures the cloud; the customer
secures what they put in the cloud.** Managed services (like RDS) shift more
work to AWS than self-managed compute (like EC2).

---

## 1. Summary table

| # | Domain | AWS | Customer | Shared | This project — who does what & why |
|---|--------|:---:|:--------:|:------:|-------------------------------------|
| 1 | Physical security (facilities, guards) | ✅ | | | AWS owns and guards the data centres; the customer has no access. |
| 2 | Data centre environmental controls | ✅ | | | Power, cooling, fire suppression are AWS-operated. |
| 3 | Hardware & host infrastructure | ✅ | | | Physical servers, storage, network gear running our VPC/EC2/RDS are AWS's. |
| 4 | Virtualization / hypervisor | ✅ | | | AWS isolates tenants at the hypervisor; not customer-accessible. |
| 5 | Global network backbone / DDoS (infra) | ✅ | | | AWS operates the backbone and baseline (Shield Standard) protection. |
| 6 | Managed-service host OS & DB engine patching (RDS) | ✅ | | | RDS host OS and MySQL engine patching is AWS's job; we only pick versions/windows. |
| 7 | **VPC design & network segmentation** | | ✅ | | We define the VPC, subnets, public/private/isolated split (`vpc.tf`, `subnets.tf`). |
| 8 | **Route tables / internet exposure** | | ✅ | | We decide IGW/NAT routing and that the DB has no internet route (`routes.tf`). |
| 9 | **Security Groups (firewall rules)** | | ✅ | | We author every least-privilege rule (`security_groups.tf`). |
| 10 | **IAM roles, policies, least privilege** | | ✅ | | We create the app role and scope it to one SSM parameter (`application.tf`). AWS enforces the IAM service itself. |
| 11 | Guest OS patching (EC2 app tier) | | ✅ | | The EC2 OS is ours; we patch via `dnf update` / AMI refresh. |
| 12 | Application security (our web app) | | ✅ | | The `httpd` app and its code/config are entirely ours. |
| 13 | **Database security configuration** | | | ✅ | AWS secures the engine/host; we set `publicly_accessible=false`, SG, subnet group, users. |
| 14 | **Encryption at rest** | | | ✅ | AWS provides KMS + the capability; we must *enable* it (`storage_encrypted`, EBS `encrypted`). |
| 15 | **Encryption in transit** | | | ✅ | AWS provides TLS-capable endpoints; we must configure HTTPS/TLS (demo uses HTTP — see note). |
| 16 | **Secrets management** | | | ✅ | AWS provides SSM/KMS; we must store the DB password there and grant least-privilege reads. |
| 17 | Key management (KMS infrastructure) | ✅ | | | AWS operates KMS HSMs and durability; we choose/authorise keys. |
| 18 | **Logging configuration** | | | ✅ | AWS can emit CloudTrail/Flow Logs/ALB logs; we must enable/route/retain them. |
| 19 | **Monitoring & alerting** | | | ✅ | AWS provides CloudWatch/GuardDuty; we define metrics, alarms, and act on them. |
| 20 | **Backups** | | | ✅ | AWS runs the RDS backup machinery; we set retention (`backup_retention_period=7`) and test restores. |
| 21 | Backup infrastructure durability | ✅ | | | AWS guarantees the durability/availability of the backup storage itself. |
| 22 | **Access control (who can reach what)** | | | ✅ | AWS enforces IAM/SG; we define the principals, rules, and the no-SSH/SSM decision. |
| 23 | **Vulnerability management** | | | ✅ | AWS patches managed layers; we patch our EC2 OS/app and can run Inspector. |
| 24 | **Data protection & classification** | | ✅ | | The data we store in RDS and its handling/retention is our responsibility. |
| 25 | **Incident response** | | | ✅ | AWS handles infra incidents & tooling; we own detection and response for our workload. |
| 26 | Availability of the AWS services themselves | ✅ | | | AWS meets the service SLAs for ALB/EC2/RDS. |
| 27 | **Availability/HA design of our workload** | | ✅ | | We chose multi-AZ subnets, an ASG, and the `db_multi_az` option. |
| 28 | **Cost & resource governance** | | ✅ | | We decide instance sizes, NAT count, and tear-down to control spend. |

---

## 2. Detailed explanations

### 2.1 Domains AWS owns ("security *of* the cloud")

- **Physical & environmental (1, 2):** Data centres, physical access controls,
  power, cooling and fire suppression are entirely AWS-operated. As a customer I
  cannot and do not manage them.
- **Hardware, hypervisor, backbone (3, 4, 5):** The physical hosts running my
  EC2 instances and RDS, the virtualization layer that isolates tenants, and the
  global network (including Shield Standard DDoS protection) are AWS's
  responsibility.
- **RDS engine/host patching (6):** Because RDS is a **managed** service, AWS
  patches the underlying OS and the MySQL engine binaries. My only input is
  choosing the engine version and allowing minor-version upgrades
  (`auto_minor_version_upgrade = true`) and maintenance windows.
- **KMS & backup-storage infrastructure (17, 21):** AWS runs the key-management
  hardware and guarantees the durability of backup storage.
- **Service availability/SLAs (26):** AWS is responsible for keeping ALB, EC2,
  and RDS themselves available per their SLAs.

### 2.2 Domains I own ("security *in* the cloud")

- **VPC design & segmentation (7):** I designed the `10.0.0.0/16` VPC and split
  it into public, private, and isolated subnet groups across two AZs. AWS gives
  me the capability; the topology is my decision.
- **Routing & exposure (8):** I decided the IGW routes only the public subnets,
  the NAT gives the app tier outbound-only access, and the DB subnets have **no**
  internet route. That isolation is a direct result of my route-table design.
- **Security Groups (9):** Every rule is mine. I implemented the
  `internet→ALB→app→DB` least-privilege chain using SG references so the database
  accepts traffic only from the app tier.
- **IAM (10):** I created the app instance role and restricted it to reading a
  single SSM parameter. AWS enforces IAM as a service, but the policies are mine.
- **Guest OS & app (11, 12):** The EC2 Amazon Linux OS and the `httpd`
  application are self-managed; patching and app security are on me.
- **Data protection (24):** Whatever data lands in the database and how it is
  classified, retained, or deleted is my responsibility.
- **Workload HA & cost (27, 28):** Multi-AZ layout, the ASG, the `db_multi_az`
  choice, instance sizing, NAT-gateway count, and tearing the stack down to
  avoid charges are all my decisions.

### 2.3 Shared domains (boundary explained)

- **Database security configuration (13):** AWS secures the engine and host; I
  configure `publicly_accessible = false`, the DB security group, the isolated
  subnet group, and database users/privileges.
- **Encryption at rest (14):** AWS supplies KMS and the encryption capability,
  but it only protects data if I **enable** it — which I did on RDS storage and
  the EC2 root volume.
- **Encryption in transit (15):** AWS endpoints support TLS, but configuring
  HTTPS is my job. *This demo uses HTTP:80 on the ALB to avoid a domain/cert
  requirement; production should use HTTPS:443 + ACM.* I state this rather than
  claim full in-transit encryption.
- **Secrets management (16):** AWS provides SSM Parameter Store and KMS; I am
  responsible for actually storing the DB password there (as a SecureString) and
  granting only least-privilege read access to the app role.
- **Logging & monitoring (18, 19):** AWS can produce CloudTrail events, VPC Flow
  Logs, ALB access logs, and CloudWatch/GuardDuty findings, but I must enable,
  route, retain, and act on them. (Enabled selectively here to control cost.)
- **Backups (20):** AWS runs the backup engine for RDS; I set the retention
  period and am responsible for testing that restores actually work.
- **Access control (22):** AWS enforces IAM and security groups; I define who
  and what may connect, including the decision to use SSM Session Manager
  instead of SSH.
- **Vulnerability management (23):** AWS patches the managed layers; I patch my
  EC2 OS/app and could add Amazon Inspector for scanning.
- **Incident response (25):** AWS handles incidents affecting its infrastructure
  and provides tooling; detecting and responding to incidents in *my* workload
  is my responsibility.

---

## 3. One-line takeaway

> In this project AWS secures the **facilities, hardware, hypervisor, managed
> RDS engine, and service availability**, while I secure the **VPC design,
> segmentation, security groups, IAM, OS/app, encryption enablement, secrets,
> and monitoring** — with database config, encryption, secrets, logging,
> backups, access control, vulnerability management, and incident response
> **shared** along a clearly defined line.
