#!/bin/bash
# n8n bootstrap — Amazon Linux 2023 ARM64 (Graviton)
# Runs once on first boot via EC2 user data.
#
# Architecture:
#   ALB (TLS termination) → EC2:5678 (n8n) → localhost postgres
#   All persistent data on EFS (survives instance replacement)
#   Secrets from SSM (never written to disk in plaintext)
#   Custom n8n image from ECR (includes cheerio)

set -euo pipefail
exec > >(tee /var/log/n8n-init.log | logger -t n8n-init) 2>&1

echo "=== n8n bootstrap started at $(date) ==="

# ── 1. System packages ────────────────────────────────────────────────────
dnf update -y
dnf install -y docker amazon-cloudwatch-agent amazon-efs-utils cronie jq

systemctl enable --now docker crond
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

# Mount all EFS volumes (retry for mount target propagation)
for mp in /mnt/efs/n8n-data /mnt/efs/local-files /mnt/efs/postgres-data; do
  for attempt in 1 2 3 4 5; do
    if mount "$mp" 2>/dev/null; then
      echo "Mounted $mp"
      break
    fi
    echo "Mount attempt $attempt for $mp failed, retrying in 15s..."
    sleep 15
  done
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

# ── 7. Docker Compose file ────────────────────────────────────────────────
# n8n listens on 5678 — ALB forwards to this port.
# No Traefik — TLS is terminated by the ALB with an ACM certificate.
# Postgres runs alongside n8n on localhost — data on EFS.
cat > /opt/n8n/docker-compose.yml << 'COMPOSEEOF'
name: n8n

services:
  n8n:
    image: ${ecr_repo_url}:${ecr_image_tag}
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      - N8N_HOST=${fqdn}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${fqdn}/
      - NODE_ENV=production
      - GENERIC_TIMEZONE=${timezone}
      - TZ=${timezone}
      - N8N_RUNNERS_ENABLED=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      # ALB adds one proxy hop
      - N8N_PROXY_HOPS=1
      # Node.js heap — 75% of instance memory (t4g.small = 2 GB → 1536 MB)
      - NODE_OPTIONS=--max-old-space-size=1536
      - NODE_FUNCTION_ALLOW_EXTERNAL=cheerio
      # Database
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n_user
      # Secrets injected via Docker Compose env_file or shell env
      # (set by systemd EnvironmentFile pointing to /run/n8n/secrets.env)
    volumes:
      - /mnt/efs/n8n-data:/home/node/.n8n
      - /mnt/efs/local-files:/files
    networks:
      - n8n_net
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: n8n_user
    volumes:
      - /mnt/efs/postgres-data:/var/lib/postgresql/data
    networks:
      - n8n_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n_user -d n8n"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes: {}

networks:
  n8n_net:
    driver: bridge
COMPOSEEOF
echo "Docker Compose file written"

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
  REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region) && \
  DB_PASS=$(aws ssm get-parameter --region $REGION --name "${db_password_param}" --with-decryption --query Parameter.Value --output text) && \
  ENC_KEY=$(aws ssm get-parameter --region $REGION --name "${encryption_key_param}" --with-decryption --query Parameter.Value --output text) && \
  printf "DB_POSTGRESDB_PASSWORD=%s\nN8N_ENCRYPTION_KEY=%s\nPOSTGRES_PASSWORD=%s\n" "$DB_PASS" "$ENC_KEY" "$DB_PASS" > /run/n8n/secrets.env && \
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
# Load secrets into environment, then pass to docker compose
EnvironmentFile=/run/n8n/secrets.env
ExecStart=/bin/bash -c 'export $(cat /run/n8n/secrets.env | xargs) && docker compose up -d'
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
  pg_dump -U n8n_user n8n > "$BACKUP_DIR/postgres.sql"

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

# ── 12. n8n image update script ───────────────────────────────────────────
cat > /opt/n8n/update-n8n.sh << 'UPDATEEOF'
#!/bin/bash
# Pull latest custom n8n image from ECR and restart.
# Usage: sudo /opt/n8n/update-n8n.sh
set -euo pipefail

REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
ECR_REGISTRY=$(echo "${ecr_repo_url}" | cut -d/ -f1)

echo "Authenticating to ECR..."
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

echo "Pulling latest image..."
docker compose -f /opt/n8n/docker-compose.yml pull n8n

echo "Restarting n8n..."
export $(cat /run/n8n/secrets.env | xargs)
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

docker compose pull
docker compose up -d

# Write secrets to tmpfs for systemd (same as n8n-secrets.service does on reboot)
mkdir -p /run/n8n && chmod 700 /run/n8n
printf "DB_POSTGRESDB_PASSWORD=%s\nN8N_ENCRYPTION_KEY=%s\nPOSTGRES_PASSWORD=%s\n" \
  "$DB_PASS" "$ENC_KEY" "$DB_PASS" > /run/n8n/secrets.env
chmod 600 /run/n8n/secrets.env

echo "=== n8n bootstrap completed at $(date) ==="
echo "URL: https://${fqdn} (once ALB health check passes)"
echo "Check: docker compose -f /opt/n8n/docker-compose.yml ps"
echo "Logs:  docker compose -f /opt/n8n/docker-compose.yml logs -f n8n"
