#!/bin/bash
# n8n bootstrap script — Amazon Linux 2023 ARM64 (Graviton)
# Runs once on first boot via EC2 user data.
#
# Terraform templatefile() variables substituted before execution:
#   $${aws_region}           AWS region (e.g. eu-west-2)
#   $${fqdn}                 Full hostname (e.g. n8n.taurak.co.uk)
#   $${ssl_email}            Let's Encrypt contact email
#   $${timezone}             Timezone string (e.g. Europe/London)
#   $${backup_bucket}        S3 bucket for backups
#   $${db_password_param}    SSM parameter path for DB password
#   $${encryption_key_param} SSM parameter path for n8n encryption key
#   $${cloudwatch_log_group} CloudWatch log group name

set -euo pipefail

# Send all output to syslog AND a log file for CloudWatch ingestion
exec > >(tee /var/log/n8n-init.log | logger -t n8n-init) 2>&1

echo "=== n8n bootstrap started at $(date) ==="

# ── 1. System updates and packages ────────────────────────────────────────
dnf update -y
dnf install -y docker amazon-cloudwatch-agent cronie

systemctl enable --now docker crond

# Allow ec2-user to run docker without sudo (takes effect on next login)
usermod -aG docker ec2-user

# ── 2. Docker Compose v2 plugin (ARM64 binary) ────────────────────────────
COMPOSE_VER="v2.27.0"
COMPOSE_DIR="/usr/local/lib/docker/cli-plugins"
mkdir -p "$COMPOSE_DIR"

curl -fsSL \
  "https://github.com/docker/compose/releases/download/$COMPOSE_VER/docker-compose-linux-aarch64" \
  -o "$COMPOSE_DIR/docker-compose"
chmod +x "$COMPOSE_DIR/docker-compose"

docker compose version
echo "Docker Compose installed"

# ── 3. Fetch secrets from SSM ─────────────────────────────────────────────
# Retry up to 5 times to handle IAM role propagation delays at cold start.
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
  echo "ERROR: failed to fetch SSM parameter $param after 5 attempts" >&2
  return 1
}

DB_PASS=$(fetch_ssm "${db_password_param}")
ENC_KEY=$(fetch_ssm "${encryption_key_param}")
echo "SSM parameters fetched successfully"

# ── 4. Application directory structure ───────────────────────────────────
mkdir -p /opt/n8n/{letsencrypt,local-files,backups}

# Traefik requires acme.json to be owned by root with mode 600
touch /opt/n8n/letsencrypt/acme.json
chmod 600 /opt/n8n/letsencrypt/acme.json

# ── 5. Environment file ───────────────────────────────────────────────────
# Unquoted heredoc: bash expands $DB_PASS and $ENC_KEY at write time.
# Docker Compose reads this file for variable substitution.
# chmod 600 keeps secrets off of world-readable permissions.
cat > /opt/n8n/.env << ENVEOF
# PostgreSQL credentials (used by both the postgres container and n8n)
POSTGRES_DB=n8n
POSTGRES_USER=n8n_user
POSTGRES_PASSWORD=$DB_PASS

# n8n application settings
N8N_ENCRYPTION_KEY=$ENC_KEY
N8N_HOST=${fqdn}
N8N_PROTOCOL=https
WEBHOOK_URL=https://${fqdn}
# N8N_PROXY_HOPS=0 because Traefik terminates TLS on the same host (no ALB hop)
N8N_PROXY_HOPS=0
GENERIC_TIMEZONE=${timezone}
TZ=${timezone}
N8N_RUNNERS_ENABLED=true
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
# Cap Node.js heap to 3 GB; leaves ~1 GB headroom on a 4 GB instance
NODE_OPTIONS=--max-old-space-size=3072

# PostgreSQL connection for n8n
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=$DB_PASS
ENVEOF
chmod 600 /opt/n8n/.env
echo "Environment file written"

# ── 6. Docker Compose file ────────────────────────────────────────────────
# Quoted heredoc: bash does NOT expand variables.
# Terraform has already substituted: ${fqdn}, ${ssl_email}, ${timezone}.
# $${POSTGRES_PASSWORD} in the template renders as ${POSTGRES_PASSWORD} here;
# Docker Compose then substitutes it from .env at startup time.
# Traefik Host() uses double-quote syntax (supported since v2.4) to avoid
# backtick interpretation issues in shell heredocs.
cat > /opt/n8n/docker-compose.yml << 'COMPOSEEOF'
name: n8n

services:
  traefik:
    image: traefik:v3.0
    restart: unless-stopped
    command:
      - --log.level=INFO
      - --api=false
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.scheme=https
      - --entrypoints.web.http.redirections.entrypoint.permanent=true
      - --certificatesresolvers.letsencrypt.acme.email=${ssl_email}
      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json
      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/n8n/letsencrypt:/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - n8n_net

  n8n:
    image: docker.n8n.io/n8nio/n8n:stable
    restart: unless-stopped
    env_file: /opt/n8n/.env
    volumes:
      - n8n_data:/home/node/.n8n
      - /opt/n8n/local-files:/files
    networks:
      - n8n_net
    depends_on:
      postgres:
        condition: service_healthy
    labels:
      - traefik.enable=true
      - traefik.http.routers.n8n.rule=Host("${fqdn}")
      - traefik.http.routers.n8n.entrypoints=websecure
      - traefik.http.routers.n8n.tls.certresolver=letsencrypt
      - traefik.http.services.n8n.loadbalancer.server.port=5678
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
      # Docker Compose reads POSTGRES_PASSWORD from .env in the working directory
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - n8n_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U n8n_user -d n8n"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  n8n_data:
  postgres_data:

networks:
  n8n_net:
    driver: bridge
COMPOSEEOF
echo "Docker Compose file written"

# ── 7. Systemd service for auto-start on reboot ───────────────────────────
cat > /etc/systemd/system/n8n.service << 'SERVICEEOF'
[Unit]
Description=n8n workflow automation (Docker Compose)
After=docker.service network-online.target
Requires=docker.service
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable n8n.service
echo "Systemd service registered"

# ── 8. CloudWatch agent configuration ────────────────────────────────────
# ${cloudwatch_log_group} is substituted by Terraform.
# {instance_id} is a CloudWatch agent built-in placeholder (no $ prefix).
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
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
echo "CloudWatch agent configured and started"

# ── 9. Backup script ──────────────────────────────────────────────────────
# Quoted heredoc: bash does not expand variables, so $TIMESTAMP etc. remain
# as shell variable references in the written script.
# ${backup_bucket} and ${aws_region} are substituted by Terraform.
cat > /opt/n8n/backup.sh << 'BACKUPEOF'
#!/bin/bash
# n8n backup script — dumps PostgreSQL and archives n8n data volume to S3.
# Prefixes: daily (7-day retention), weekly/Sunday (28-day), monthly/1st (365-day).
set -euo pipefail

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=/tmp/n8n-backup-$TIMESTAMP
BUCKET=${backup_bucket}

echo "=== Backup started: $TIMESTAMP ==="
mkdir -p "$BACKUP_DIR"

# Dump PostgreSQL (runs inside the running postgres container)
docker compose -f /opt/n8n/docker-compose.yml exec -T postgres \
  pg_dump -U n8n_user n8n > "$BACKUP_DIR/postgres.sql"

# Archive n8n data volume.
# Project name is "n8n" (set via `name:` in docker-compose.yml),
# so Docker names the volume "n8n_n8n_data".
docker run --rm \
  -v n8n_n8n_data:/data:ro \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/n8n_data.tar.gz -C /data .

# Determine S3 prefix based on schedule
DOW=$(date +%u)    # 1=Monday … 7=Sunday
DOM=$(date +%-d)   # Day of month without leading zero
if [ "$DOM" = "1" ]; then
  PREFIX=monthly
elif [ "$DOW" = "7" ]; then
  PREFIX=weekly
else
  PREFIX=daily
fi

# Upload to S3
aws s3 cp "$BACKUP_DIR/postgres.sql" \
  "s3://$BUCKET/$PREFIX/$TIMESTAMP/postgres.sql" \
  --region ${aws_region}

aws s3 cp "$BACKUP_DIR/n8n_data.tar.gz" \
  "s3://$BUCKET/$PREFIX/$TIMESTAMP/n8n_data.tar.gz" \
  --region ${aws_region}

# Remove local temp directory
rm -rf "$BACKUP_DIR"

echo "=== Backup completed: $PREFIX/$TIMESTAMP ==="
BACKUPEOF
chmod +x /opt/n8n/backup.sh
echo "Backup script written"

# ── 10. Backup cron job (daily at 03:00 UTC) ──────────────────────────────
echo "0 3 * * * root /opt/n8n/backup.sh >> /var/log/n8n-backup.log 2>&1" \
  > /etc/cron.d/n8n-backup
chmod 644 /etc/cron.d/n8n-backup
echo "Backup cron registered"

# ── 11. Pull images and start the stack ──────────────────────────────────
cd /opt/n8n
docker compose pull
docker compose up -d

echo "=== n8n bootstrap completed at $(date) ==="
echo "Stack URL: https://${fqdn}"
echo "Check status: docker compose -f /opt/n8n/docker-compose.yml ps"
echo "View logs:    docker compose -f /opt/n8n/docker-compose.yml logs -f n8n"
