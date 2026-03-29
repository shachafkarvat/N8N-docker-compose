#!/bin/bash
# n8n bootstrap — Amazon Linux 2023 ARM64 (Graviton)
# Runs once on first boot via EC2 user data.
#
# Architecture:
#   ALB mode:    ALB (TLS termination) → EC2:5678 (n8n) → localhost postgres
#   Direct mode: Internet → nginx (ACM TLS) → n8n → localhost postgres
#   All persistent data on EFS (survives instance replacement)
#   Secrets from SSM (never written to disk in plaintext)
#   Custom n8n image from ECR (includes cheerio)

set -euo pipefail
exec > >(tee /var/log/n8n-init.log | logger -t n8n-init) 2>&1

echo "=== n8n bootstrap started at $(date) ==="

# ── 1. System packages ────────────────────────────────────────────────────
dnf update -y
dnf install -y docker amazon-cloudwatch-agent amazon-efs-utils amazon-ssm-agent cronie jq openssl pip
pip3 install botocore   # EFS mount helper uses botocore to resolve mount-target IPs

systemctl enable --now docker crond amazon-ssm-agent
usermod -aG docker ec2-user

# ── 2. Docker Compose v2 plugin (ARM64) ───────────────────────────────────
COMPOSE_VER="v2.29.0"
COMPOSE_DIR="/usr/local/lib/docker/cli-plugins"
mkdir -p "$COMPOSE_DIR"
curl -fsSL \
  "https://github.com/docker/compose/releases/download/$COMPOSE_VER/docker-compose-linux-aarch64" \
  -o "$COMPOSE_DIR/docker-compose"
chmod +x "$COMPOSE_DIR/docker-compose"
docker compose version
echo "Docker Compose installed"

# ── 3. Mount EFS ──────────────────────────────────────────────────────────
# Three mount points via EFS access points:
#   /mnt/efs/n8n-data       → n8n application data (/home/node/.n8n)
#   /mnt/efs/local-files    → workflow file I/O (/files)
#   /mnt/efs/postgres-data  → PostgreSQL data directory

mkdir -p /mnt/efs/n8n-data /mnt/efs/local-files /mnt/efs/postgres-data

# Add fstab entries (mount on boot, TLS encrypted)
cat >> /etc/fstab << FSTABEOF
${efs_id}:/ /mnt/efs/n8n-data efs _netdev,tls,accesspoint=${efs_ap_n8n_data} 0 0
${efs_id}:/ /mnt/efs/local-files efs _netdev,tls,accesspoint=${efs_ap_local_files} 0 0
${efs_id}:/ /mnt/efs/postgres-data efs _netdev,tls,accesspoint=${efs_ap_postgres} 0 0
FSTABEOF

# Mount all EFS volumes (retry for mount target propagation / DNS)
for mp in /mnt/efs/n8n-data /mnt/efs/local-files /mnt/efs/postgres-data; do
  mounted=false
  for attempt in $(seq 1 10); do
    if mount "$mp" 2>&1; then
      echo "Mounted $mp"
      mounted=true
      break
    fi
    echo "Mount attempt $attempt for $mp failed, retrying in 30s..."
    sleep 30
  done
  if [[ "$mounted" != "true" ]]; then
    echo "ERROR: Failed to mount $mp after 10 attempts" >&2
  fi
done

echo "EFS mounted"

# ── 4. Authenticate Docker to ECR ─────────────────────────────────────────
aws ecr get-login-password --region ${aws_region} | \
  docker login --username AWS --password-stdin \
  $(echo "${ecr_repo_url}" | cut -d/ -f1)
echo "ECR authenticated"

# ── 5. Fetch secrets from SSM (never written to disk) ─────────────────────
# Secrets are passed to Docker Compose via environment variables only.
# They exist in memory (the running shell + Docker env), never in a file.
fetch_ssm() {
  local param="$1"
  local attempt value
  for attempt in 1 2 3 4 5; do
    if value=$(aws ssm get-parameter \
        --region "${aws_region}" \
        --name "$param" \
        --with-decryption \
        --query "Parameter.Value" \
        --output text 2>&1); then
      echo "$value"
      return 0
    fi
    echo "SSM fetch attempt $attempt failed for $param, retrying in 15s..." >&2
    sleep 15
  done
  echo "ERROR: failed to fetch SSM parameter $param" >&2
  return 1
}

DB_PASS=$(fetch_ssm "${db_password_param}")
ENC_KEY=$(fetch_ssm "${encryption_key_param}")
echo "SSM parameters fetched"

# ── 6. Application directory ──────────────────────────────────────────────
mkdir -p /opt/n8n

# ── 7. Runtime config sync ────────────────────────────────────────────────
# The Compose file is stored in S3 so application config can be updated
# independently of instance bootstrap. Secrets stay in SSM and are injected
# by systemd at runtime.
cat > /opt/n8n/refresh-config.sh << 'REFRESHEOF'
#!/bin/bash
set -euo pipefail

CONFIG_URI="${compose_config_s3_uri}"
TARGET="/opt/n8n/docker-compose.yml"
TMP=$(mktemp)

aws s3 cp "$CONFIG_URI" "$TMP" --region "${aws_region}" >/dev/null

if [[ -f "$TARGET" ]] && cmp -s "$TMP" "$TARGET"; then
  rm -f "$TMP"
  echo "Compose config already up to date"
  exit 0
fi

install -m 0644 "$TMP" "$TARGET"
rm -f "$TMP"
echo "Compose config refreshed from S3"
REFRESHEOF
chmod +x /opt/n8n/refresh-config.sh

cat > /opt/n8n/refresh-acm-certificate.sh << 'ACMEOF'
#!/bin/bash
set -euo pipefail

if [[ "${enable_alb}" == "true" ]]; then
  echo "ALB mode enabled; ACM certificate remains attached to the load balancer"
  exit 0
fi

TLS_DIR="/run/n8n/tls"
PASSFILE="$TLS_DIR/passphrase.txt"
EXPORT_JSON="$TLS_DIR/export.json"
ENC_KEY="$TLS_DIR/private-key.encrypted.pem"
KEYFILE="$TLS_DIR/tls.key"
CERTFILE="$TLS_DIR/tls.crt"
CHAINFILE="$TLS_DIR/chain.crt"
FULLCHAINFILE="$TLS_DIR/fullchain.crt"

mkdir -p "$TLS_DIR"
chmod 700 "$TLS_DIR"

printf '%s' "$(openssl rand -hex 32)" > "$PASSFILE"

aws acm export-certificate \
  --region "${aws_region}" \
  --certificate-arn "${acm_certificate_arn}" \
  --passphrase "fileb://$PASSFILE" \
  --output json > "$EXPORT_JSON"

jq -r '.Certificate' "$EXPORT_JSON" > "$CERTFILE"
jq -r '.CertificateChain' "$EXPORT_JSON" > "$CHAINFILE"
jq -r '.PrivateKey' "$EXPORT_JSON" > "$ENC_KEY"
openssl pkey -in "$ENC_KEY" -out "$KEYFILE" -passin "file:$PASSFILE" >/dev/null 2>&1
cat "$CERTFILE" "$CHAINFILE" > "$FULLCHAINFILE"

chmod 600 "$KEYFILE" "$CERTFILE" "$CHAINFILE" "$FULLCHAINFILE"
rm -f "$PASSFILE" "$EXPORT_JSON" "$ENC_KEY"
echo "ACM certificate exported to $TLS_DIR"
ACMEOF
chmod +x /opt/n8n/refresh-acm-certificate.sh

cat > /opt/n8n/nginx.conf << 'NGINXEOF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  '' close;
}

server {
  listen 80;
  server_name ${fqdn};
  return 301 https://$host$request_uri;
}

server {
  listen 443 ssl http2;
  server_name ${fqdn};

  ssl_certificate /run/n8n/tls/fullchain.crt;
  ssl_certificate_key /run/n8n/tls/tls.key;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers off;

  client_max_body_size 64m;
  proxy_read_timeout 3600s;
  proxy_send_timeout 3600s;

  location / {
    proxy_pass http://n8n:5678;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
  }
}
NGINXEOF

/opt/n8n/refresh-config.sh

# ACM certificate may not be issued yet if DNS validation is still propagating.
# Retry with backoff so the rest of the bootstrap is not blocked.
for cert_attempt in $(seq 1 12); do
  if /opt/n8n/refresh-acm-certificate.sh 2>&1; then
    break
  fi
  echo "ACM cert export attempt $cert_attempt failed, retrying in 30s..."
  sleep 30
done
echo "Docker Compose file downloaded"

# ── 8. Systemd service with secrets injection ─────────────────────────────
# Secrets are written to a tmpfs file at service start and removed at stop.
# /run is tmpfs — nothing persists across reboots.
cat > /etc/systemd/system/n8n-secrets.service << 'SECRETSEOF'
[Unit]
Description=Fetch n8n secrets from SSM and write to tmpfs
Before=n8n.service

[Service]
Type=oneshot
RemainAfterExit=yes

ExecStart=/bin/bash -c '\
  mkdir -p /run/n8n && chmod 700 /run/n8n && \
  REGION=${aws_region} && \
  DB_PASS=$(aws ssm get-parameter --region $REGION --name "${db_password_param}" --with-decryption --query Parameter.Value --output text) && \
  ENC_KEY=$(aws ssm get-parameter --region $REGION --name "${encryption_key_param}" --with-decryption --query Parameter.Value --output text) && \
  printf "DB_POSTGRESDB_PASSWORD=%%s\nN8N_ENCRYPTION_KEY=%%s\nPOSTGRES_PASSWORD=%%s\n" "$DB_PASS" "$ENC_KEY" "$DB_PASS" > /run/n8n/secrets.env && \
  chmod 600 /run/n8n/secrets.env'

ExecStop=/bin/rm -f /run/n8n/secrets.env

[Install]
WantedBy=multi-user.target
SECRETSEOF

cat > /etc/systemd/system/n8n.service << 'SERVICEEOF'
[Unit]
Description=n8n workflow automation (Docker Compose)
After=docker.service network-online.target n8n-secrets.service
Requires=docker.service n8n-secrets.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
# Load secrets into environment, refresh Compose config from S3, then start.
EnvironmentFile=/run/n8n/secrets.env
ExecStart=/bin/bash -c '/opt/n8n/refresh-config.sh && /opt/n8n/refresh-acm-certificate.sh && docker compose config >/dev/null && docker compose up -d'
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable n8n-secrets.service n8n.service
echo "Systemd services registered"

# ── 9. CloudWatch agent ───────────────────────────────────────────────────
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/n8n-init.log",
            "log_group_name": "${cloudwatch_log_group}",
            "log_stream_name": "init/{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/n8n-backup.log",
            "log_group_name": "${cloudwatch_log_group}",
            "log_stream_name": "backup/{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s
echo "CloudWatch agent started"

# ── 10. Backup script ─────────────────────────────────────────────────────
cat > /opt/n8n/backup.sh << 'BACKUPEOF'
#!/bin/bash
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/tmp/n8n-backup-$TIMESTAMP
BUCKET="${backup_bucket}"
REGION="${aws_region}"

echo "=== Backup started: $TIMESTAMP ==="
mkdir -p "$BACKUP_DIR"

# pg_dump via the running postgres container
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  pg_dump -U postgres n8n > "$BACKUP_DIR/postgres.sql"

# Archive n8n data from EFS
tar czf "$BACKUP_DIR/n8n_data.tar.gz" -C /mnt/efs/n8n-data .

# Determine S3 prefix
DOW=$(date +%u)
DOM=$(date +%-d)
if [ "$DOM" = "1" ]; then
  PREFIX=monthly
elif [ "$DOW" = "7" ]; then
  PREFIX=weekly
else
  PREFIX=daily
fi

# Upload
aws s3 cp "$BACKUP_DIR/postgres.sql" \
  "s3://$BUCKET/$PREFIX/$TIMESTAMP/postgres.sql" --region "$REGION"
aws s3 cp "$BACKUP_DIR/n8n_data.tar.gz" \
  "s3://$BUCKET/$PREFIX/$TIMESTAMP/n8n_data.tar.gz" --region "$REGION"

rm -rf "$BACKUP_DIR"
echo "=== Backup completed: $PREFIX/$TIMESTAMP ==="
BACKUPEOF
chmod +x /opt/n8n/backup.sh
echo "Backup script written"

# ── 11. Backup cron (02:00 UTC — matches Asgard schedule) ────────────────
echo "0 2 * * * root /opt/n8n/backup.sh >> /var/log/n8n-backup.log 2>&1" \
  > /etc/cron.d/n8n-backup
chmod 644 /etc/cron.d/n8n-backup
echo "Backup cron registered"

cat > /etc/cron.d/n8n-cert-refresh << 'CERTREFRESHEOF'
15 3 * * * root if [ "${enable_alb}" = "false" ]; then /opt/n8n/refresh-acm-certificate.sh && docker compose -f /opt/n8n/docker-compose.yml up -d edge >> /var/log/n8n-cert-refresh.log 2>&1; fi
CERTREFRESHEOF
chmod 644 /etc/cron.d/n8n-cert-refresh
echo "Certificate refresh cron registered"

# ── 12. n8n image update script ───────────────────────────────────────────
cat > /opt/n8n/update-n8n.sh << 'UPDATEEOF'
#!/bin/bash
# Pull latest custom n8n image from ECR and restart.
# Usage: sudo /opt/n8n/update-n8n.sh
set -euo pipefail

REGION="${aws_region}"
ECR_REGISTRY=$(echo "${ecr_repo_url}" | cut -d/ -f1)

echo "Refreshing Compose config from S3..."
/opt/n8n/refresh-config.sh

echo "Authenticating to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Pulling latest image..."
docker compose -f /opt/n8n/docker-compose.yml pull n8n

echo "Restarting n8n..."
set -a
source /run/n8n/secrets.env
set +a
docker compose -f /opt/n8n/docker-compose.yml config >/dev/null
docker compose -f /opt/n8n/docker-compose.yml up -d n8n

echo "Done. Check: docker compose -f /opt/n8n/docker-compose.yml logs -f n8n"
UPDATEEOF
chmod +x /opt/n8n/update-n8n.sh
echo "Update script written"

# ── 13. Pull images and start ─────────────────────────────────────────────
cd /opt/n8n

# Export secrets for initial docker compose up
export DB_POSTGRESDB_PASSWORD="$DB_PASS"
export N8N_ENCRYPTION_KEY="$ENC_KEY"
export POSTGRES_PASSWORD="$DB_PASS"

docker compose config >/dev/null
docker compose pull
docker compose up -d

# Write secrets to tmpfs for systemd (same as n8n-secrets.service does on reboot)
mkdir -p /run/n8n && chmod 700 /run/n8n
printf "DB_POSTGRESDB_PASSWORD=%s\nN8N_ENCRYPTION_KEY=%s\nPOSTGRES_PASSWORD=%s\n" \
  "$DB_PASS" "$ENC_KEY" "$DB_PASS" > /run/n8n/secrets.env
chmod 600 /run/n8n/secrets.env

echo "=== n8n bootstrap completed at $(date) ==="
echo "URL: https://${fqdn}"
echo "Check: docker compose -f /opt/n8n/docker-compose.yml ps"
echo "Logs:  docker compose -f /opt/n8n/docker-compose.yml logs -f n8n"
