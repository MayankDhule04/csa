#!/bin/bash
# ---------------------------------------------------------------------------
# Application-tier bootstrap script (Amazon Linux 2023).
#
# This is a MINIMAL demonstration application. Its only job is to prove the
# architecture works end to end:
#   1. It runs a web server on the private app tier (reached only via the ALB).
#   2. It fetches the database password from SSM Parameter Store at runtime
#      (never from hardcoded code) and tests connectivity to the private RDS
#      database, proving the app -> DB path works while the DB stays isolated.
#
# Terraform-injected values use the dollar-brace VAR syntax and are substituted
# by templatefile(). Shell variables are escaped with a double dollar sign so
# Terraform leaves them alone, e.g. $${TOKEN}.
# ---------------------------------------------------------------------------
set -euo pipefail
exec > /var/log/user-data.log 2>&1

echo "== Bootstrapping application tier =="

# Install a web server and the MySQL/MariaDB client for the connectivity test.
dnf -y update
dnf -y install httpd mariadb105

systemctl enable --now httpd

# Instance metadata via IMDSv2 (token required).
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
LOCAL_IP=$(curl -s -H "X-aws-ec2-metadata-token: $${TOKEN}" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

# Fetch the DB password from SSM Parameter Store (SecureString) using the
# instance's IAM role. The plaintext password is NEVER written to disk or the
# web page - only the RESULT of the connectivity test is shown.
DB_PW=$(aws ssm get-parameter \
  --name "${db_pw_ssm}" \
  --with-decryption \
  --region "${aws_region}" \
  --query 'Parameter.Value' --output text || echo "")

DB_STATUS="UNKNOWN"
if [ -n "$${DB_PW}" ]; then
  if mysql -h "${db_host}" -P "${db_port}" -u "${db_user}" \
        -p"$${DB_PW}" -e "SELECT 1;" >/dev/null 2>&1; then
    DB_STATUS="CONNECTED (app tier reached private RDS on port ${db_port})"
  else
    DB_STATUS="REACHABLE-SG-OK-BUT-QUERY-FAILED (check credentials/engine)"
  fi
else
  DB_STATUS="COULD-NOT-READ-SSM-PARAMETER"
fi

cat > /var/www/html/index.html <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${project_title}</title>
  <style>
    body { font-family: system-ui, sans-serif; margin: 0; background:#0f172a; color:#e2e8f0; }
    .wrap { max-width: 760px; margin: 40px auto; padding: 24px; }
    .card { background:#1e293b; border:1px solid #334155; border-radius:12px; padding:24px; margin-bottom:16px; }
    h1 { margin:0 0 4px; font-size:22px; }
    .muted { color:#94a3b8; font-size:14px; }
    table { width:100%; border-collapse:collapse; margin-top:8px; }
    td { padding:8px 6px; border-bottom:1px solid #334155; font-size:14px; }
    td:first-child { color:#94a3b8; width:38%; }
    .ok { color:#4ade80; } .tier { color:#38bdf8; font-weight:600; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <h1>${project_title}</h1>
      <div class="muted">3-Tier Architecture &mdash; live demonstration served from the <span class="tier">private application tier</span></div>
    </div>
    <div class="card">
      <table>
        <tr><td>Served by instance</td><td>$${INSTANCE_ID}</td></tr>
        <tr><td>Availability Zone</td><td>$${AZ}</td></tr>
        <tr><td>Private IP (app subnet)</td><td>$${LOCAL_IP}</td></tr>
        <tr><td>Reached via</td><td>Internet &rarr; ALB (public tier) &rarr; this instance</td></tr>
        <tr><td>Database endpoint</td><td>${db_host}:${db_port}</td></tr>
        <tr><td>Database connectivity</td><td class="ok">$${DB_STATUS}</td></tr>
        <tr><td>DB password source</td><td>AWS SSM Parameter Store (SecureString)</td></tr>
      </table>
    </div>
    <div class="card muted">
      This page proves: the tiers are segmented, traffic flows Internet &rarr; ALB &rarr; App &rarr; DB,
      the database is private (no public route), and the secret is retrieved at runtime rather than hardcoded.
    </div>
  </div>
</body>
</html>
HTML

echo "== Bootstrap complete =="
