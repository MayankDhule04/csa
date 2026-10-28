# Screenshots / Evidence Checklist

Capture the screenshots below **after** you run `terraform apply`. Save each
image in this folder using the suggested filename. Do **not** fabricate these —
they are the evidence that the infrastructure was actually built.

> Tip: in the AWS Console, set the region (top-right) to the one in your
> `terraform.tfvars` (default **us-east-1**) before taking screenshots.

| # | Filename | Where to capture | What must be visible | Why it is evidence | Proves requirement |
|---|----------|------------------|----------------------|--------------------|--------------------|
| 1 | `01-terraform-plan.png` | Terminal | Output of `terraform plan` showing resources to add | Shows the IaC actually defines the stack | Terraform / IaC |
| 2 | `02-terraform-apply.png` | Terminal | `Apply complete!` summary + outputs (ALB URL) | Confirms real deployment | Terraform build evidence |
| 3 | `03-vpc.png` | VPC → Your VPCs | `cloudsec-pbl-dev-vpc` with CIDR `10.0.0.0/16` | The VPC exists as designed | VPC design |
| 4 | `04-subnets.png` | VPC → Subnets | 6 subnets: 2 public, 2 app, 2 db across 2 AZs | Network segmentation across AZs | Subnets / segmentation / HA |
| 5 | `05-route-tables.png` | VPC → Route tables | Public RT → IGW; app RT → NAT; db RT → local only | Routing enforces isolation | Routing / isolation |
| 6 | `06-internet-gateway.png` | VPC → Internet gateways | IGW attached to the VPC | Public path exists only for public tier | Internet Gateway |
| 7 | `07-nat-gateway.png` | VPC → NAT gateways | NAT GW in a public subnet, with EIP | Outbound-only path for app tier | NAT / least exposure |
| 8 | `08-sg-alb.png` | EC2 → Security Groups → `*-alb-sg` | Inbound 80 from `0.0.0.0/0`; egress to app SG | Public entry limited to HTTP | SG least privilege |
| 9 | `09-sg-app.png` | EC2 → Security Groups → `*-app-sg` | Inbound 80 **from alb-sg** (SG ref) | App reachable only via ALB | SG least privilege |
| 10 | `10-sg-db.png` | EC2 → Security Groups → `*-db-sg` | Inbound 3306 **from app-sg** only; no public rule | DB not publicly accessible | Private DB / least privilege |
| 11 | `11-load-balancer.png` | EC2 → Load Balancers | ALB `active`, scheme `internet-facing`, 2 subnets | Web tier is the public entry | Load balancer / web tier |
| 12 | `12-target-group.png` | EC2 → Target Groups | App targets `healthy` | App tier is serving behind ALB | App tier works |
| 13 | `13-ec2-instances.png` | EC2 → Instances | 2 app instances, **no public IPv4**, in app subnets | App tier is private | App tier not public |
| 14 | `14-asg.png` | EC2 → Auto Scaling Groups | ASG desired/min/max = 2, 2 AZs | HA / self-healing app tier | HA quality |
| 15 | `15-rds.png` | RDS → Databases → `*-mysql` | Engine MySQL 8.0; **Publicly accessible = No**; encrypted | DB is private & encrypted | Private DB / encryption |
| 16 | `16-rds-subnet-group.png` | RDS → Subnet groups | Subnet group = the two isolated DB subnets | DB confined to isolated subnets | DB isolation |
| 17 | `17-ssm-parameter.png` | Systems Manager → Parameter Store | `/cloudsec-pbl/dev/db/password` type **SecureString** (do NOT reveal value) | Secret stored encrypted, not in code | Secrets management |
| 18 | `18-app-webpage.png` | Browser | The demo page at the ALB URL showing instance ID, AZ, and "Database connectivity: CONNECTED" | End-to-end path works: Internet→ALB→App→DB | Traffic flow / demonstrable |
| 19 | `19-db-not-public.png` | Terminal (optional) | `nc`/`Test-NetConnection` to the RDS endpoint on 3306 from your laptop **failing/timing out** | DB truly unreachable from internet | Private DB proof |
| 20 | `20-ssm-session.png` | Systems Manager → Session Manager (optional) | A shell session to an app instance (no SSH used) | Admin access without SSH | Access control |

## Optional bonus evidence
- `21-terraform-validate.png` — `terraform validate` returning *Success!*
- `22-terraform-destroy.png` — `Destroy complete!` (proves cleanup / cost control)

## How to view outputs again
```powershell
terraform output            # all outputs
terraform output alb_url    # just the demo URL
```
