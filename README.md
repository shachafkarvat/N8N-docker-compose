# n8n Self-Hosted Platform

This repository now contains two deployment paths for n8n:

- local and single-host Docker Compose with Traefik, PostgreSQL, and automated backups
- AWS production deployment assets under `Production-plan/terraform-ec2` for EC2, EFS, ECR, S3, Route53, and ACM

The root-level Docker Compose stack is still the local/self-hosted path. The AWS production path is documented separately in `Production-plan/terraform-ec2/README.md`.

Recent infrastructure changes are summarized in `CHANGES.md`.

## Repository Layout

### Local Docker Compose stack

The root directory contains the local/self-hosted deployment files:
- `docker-compose.yml`
- `n8n.Dockerfile`
- backup and restore scripts
- local configuration and data folders

This stack includes:
- **n8n**: Workflow automation platform
- **PostgreSQL**: Database for n8n data storage
- **Traefik**: Reverse proxy with automatic SSL certificate management
- **Backup Service**: Automated daily backups with retention management

### AWS production assets

The `Production-plan` directory contains architecture, migration, and infrastructure work for AWS deployment.

The main EC2 deployment module is:
- `Production-plan/terraform-ec2`

That module supports:
- direct instance mode with Elastic IP and ACM certificate termination inside Docker
- optional ALB mode with ACM certificate termination on the load balancer
- Spot instances with persistent request support
- EFS-backed persistent application and PostgreSQL data
- ECR-hosted custom n8n image
- S3-backed backups and runtime config artifacts

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+ recommended)
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
- **Resources**: 4GB+ RAM, 20GB+ free disk space
- **Network**: Internet connectivity and open ports 80, 443, 8080

### Verify System Compatibility
```bash
# Check Docker installation
docker --version
docker compose version

# Check available disk space
df -h

# Check open ports
sudo netstat -tulpn | grep -E ':80|:443|:8080'
```

## Local Architecture Overview

### System Components
```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Host (Ubuntu 25.04)              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Traefik   │  │     n8n     │  │ PostgreSQL  │         │
│  │   (Proxy)   │  │ (Workflow)  │  │ (Database)  │         │
│  │   :80/:443  │  │    :5678    │  │   :5432     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │            Docker Network: n8n-network             │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Volumes:                                                   │
│  - n8n_data (workflows, credentials)                       │
│  - postgres_data (database)                                │
│  - traefik_data (SSL certificates)                         │
└─────────────────────────────────────────────────────────────┘
```

### Component Roles
- **Traefik**: Reverse proxy with automatic SSL/TLS certificate generation
- **n8n**: Workflow automation engine with GPU access capability
- **PostgreSQL**: Primary database for workflow data and custom applications
- **Docker Network**: Isolated internal communication with external HTTPS access

## Local Quick Start Guide

### 1. Clone and Setup
```bash
# Navigate to the compose directory
cd /path/to/N8N/compose

# Ensure all required files are present
ls -la
# Should show: docker-compose.yml, .env.example, backup.sh, restore.sh, etc.
```

### 2. Environment Configuration
```bash
# Copy and customize environment variables
cp .env.example .env
nano .env  # Edit with your domain and credentials

# Key variables to configure:
# DOMAIN_NAME=taurak.co.uk
# SUBDOMAIN=n8n  
# SSL_EMAIL=admin@taurak.co.uk
# POSTGRES_PASSWORD=your-secure-password
# N8N_BASIC_AUTH_PASSWORD=your-admin-password
```

### 3. Deploy Stack
```bash
# Start all services
docker compose up -d

# Check service status
docker compose ps

# View logs
docker compose logs -f
```

### 4. Access n8n
- **n8n Interface**: `https://n8n.taurak.co.uk`
- **Traefik Dashboard**: `http://localhost:8081`
- **Default Login**: Username from `N8N_BASIC_AUTH_USER`, Password from `N8N_BASIC_AUTH_PASSWORD`

## AWS Production Deployment

For the AWS deployment path, use the dedicated module documentation:

- `Production-plan/terraform-ec2/README.md`

That documentation covers:
- prerequisites and Terraform bootstrap
- VPC and subnet handling
- direct edge mode versus ALB mode
- ACM certificate behavior
- Spot instance configuration
- runtime config refresh and operational commands

## Service Architecture

### Container Stack
```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Host                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │   Traefik   │  │     n8n     │  │ PostgreSQL  │         │
│  │   (Proxy)   │  │ (Workflow)  │  │ (Database)  │         │
│  │  :80/:443   │  │    :5678    │  │   :5432     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│         │                 │                 │              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │               Docker Network                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────┐                                           │
│  │   Backup    │  Volumes:                                 │
│  │ (Scheduled) │  - n8n_data (workflows, credentials)     │
│  │  Alpine     │  - postgres_data (database)              │
│  └─────────────┘  - traefik_data (SSL certificates)       │
└─────────────────────────────────────────────────────────────┘
```

### Component Details

#### Traefik (Reverse Proxy)
- **Ports**: 8080 (HTTP), 8443 (HTTPS), 8081 (Dashboard)
- **Features**: Automatic SSL certificates, HTTP to HTTPS redirect
- **Configuration**: Routes traffic to n8n based on domain/subdomain

#### n8n (Workflow Engine)
- **Port**: 5678 (internal)
- **Database**: PostgreSQL backend
- **Authentication**: Basic auth enabled
- **Features**: Runners enabled for scalable execution

#### PostgreSQL (Database)
- **Port**: 5432 (internal only)
- **Version**: 16
- **Health Check**: Automatic readiness verification
- **Data Persistence**: Docker volume

#### Backup Service (Automated)
- **Schedule**: Daily at 2:00 AM (configurable via cron)
- **Retention**: 30 days (configurable)
- **Components**: PostgreSQL dump, n8n data volume, configuration files
- **Storage**: `./backups` directory

## Backup and Restore

### Automated Backup System

The stack includes an automated backup service that runs daily at 2:00 AM and creates comprehensive backups of all important data.

#### Backup Components
The backup system captures:
1. **PostgreSQL Database**: Complete n8n database dump
2. **n8n Data Volume**: Workflows, credentials, and settings
3. **Local Files**: Content in `./local-files` directory
4. **Configuration**: `docker-compose.yml` and `.env` files

#### Backup Configuration
```yaml
# Backup service configuration in docker-compose.yml
backup:
  image: alpine:latest
  restart: "no"
  command: >
    sh -c "
      apk add --no-cache dcron postgresql-client &&
      echo '0 2 * * * cd /app && ./backup.sh' | crontab - &&
      crond -f -l 2
    "
  volumes:
    - .:/app
    - ./backups:/backups
    - n8n_data:/n8n_data:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
  environment:
    - POSTGRES_USER=${POSTGRES_USER:-n8n}
    - POSTGRES_DB=${POSTGRES_DB:-n8n}
```

#### Backup Schedule
- **Frequency**: Daily at 2:00 AM (configurable in cron expression)
- **Retention**: 30 days (configurable in backup.sh)
- **Storage**: `./backups` directory with timestamped files

### Manual Backup

#### Run Immediate Backup
```bash
# Run manual backup
./backup-manual.sh

# Or run backup script directly
./backup.sh
```

#### Backup Script Details
The `backup.sh` script performs the following operations:

1. **PostgreSQL Backup**:
   ```bash
   docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_DIR/postgres_${DATE}.sql"
   ```

2. **n8n Data Volume Backup**:
   ```bash
   docker run --rm \
     -v ${COMPOSE_PROJECT_NAME}_n8n_data:/data:ro \
     -v "$BACKUP_DIR":/backup \
     alpine:latest \
     tar czf "/backup/n8n_data_${DATE}.tar.gz" -C /data .
   ```

3. **Configuration Files**:
   ```bash
   cp docker-compose.yml "$BACKUP_DIR/docker-compose_${DATE}.yml"
   cp .env "$BACKUP_DIR/env_${DATE}.txt"
   ```

4. **Cleanup Old Backups**:
   ```bash
   find "$BACKUP_DIR" -name "*.sql" -mtime +$RETENTION_DAYS -delete
   find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
   ```

### Restore Process

#### List Available Backups
```bash
# View available backups
ls -la ./backups/backup_info_*.txt

# Check backup details
cat ./backups/backup_info_YYYYMMDD_HHMMSS.txt
```

#### Restore from Backup
```bash
# Restore using the restore script
./restore.sh YYYYMMDD_HHMMSS

# Example: Restore from backup created on August 14, 2025 at 00:01:31
./restore.sh 20250814_000131
```

#### Restore Script Process
The `restore.sh` script performs these operations:

1. **Validation**: Checks if backup files exist
2. **Confirmation**: Prompts user to confirm restoration
3. **Service Stop**: Stops all services safely
4. **Database Restore**:
   ```bash
   # Recreate database
   docker compose exec postgres psql -U postgres -c "DROP DATABASE IF EXISTS \"${POSTGRES_DB}\""
   docker compose exec postgres psql -U postgres -c "CREATE DATABASE \"${POSTGRES_DB}\""
   
   # Restore from backup
   docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" < backup_file.sql
   ```
5. **Volume Restore**:
   ```bash
   docker run --rm \
     -v compose_n8n_data:/data \
     -v "$(pwd)/backups":/backup \
     alpine:latest \
     sh -c "rm -rf /data/* && tar xzf /backup/n8n_data_${DATE}.tar.gz -C /data"
   ```
6. **Service Restart**: Starts all services and verifies functionality

#### Manual Restore Steps
If you need to restore manually:

```bash
# 1. Stop services
docker compose down

# 2. Start only PostgreSQL
docker compose up -d postgres

# 3. Restore database
docker compose exec -T postgres psql -U postgres -d postgres -c "DROP DATABASE IF EXISTS \"n8n\""
docker compose exec -T postgres psql -U postgres -d postgres -c "CREATE DATABASE \"n8n\""
docker compose exec -T postgres psql -U postgres -d n8n < ./backups/postgres_YYYYMMDD_HHMMSS.sql

# 4. Restore n8n data
docker run --rm \
  -v compose_n8n_data:/data \
  -v "$(pwd)/backups":/backup \
  alpine:latest \
  sh -c "rm -rf /data/* && tar xzf /backup/n8n_data_YYYYMMDD_HHMMSS.tar.gz -C /data"

# 5. Start all services
docker compose up -d
```

### Backup Monitoring

#### Check Backup Status
```bash
# View backup service logs
docker compose logs backup

# Check if backup service is running
docker compose ps backup

# List recent backups
ls -la ./backups/ | head -10
```

#### Backup Verification
```bash
# Verify backup file integrity
gzip -t ./backups/n8n_data_YYYYMMDD_HHMMSS.tar.gz
psql -f ./backups/postgres_YYYYMMDD_HHMMSS.sql --set ON_ERROR_STOP=on --quiet

# Check backup sizes
du -h ./backups/
```

### Backup Best Practices

1. **Regular Testing**: Test restore procedures monthly
2. **Off-site Storage**: Copy backups to external storage regularly
3. **Monitoring**: Set up alerts for backup failures
4. **Retention**: Adjust retention period based on storage capacity
5. **Encryption**: Consider encrypting backups for sensitive data

#### Example Backup Monitoring Script
```bash
#!/bin/bash
# scripts/check-backups.sh

BACKUP_DIR="./backups"
TODAY=$(date +%Y%m%d)

# Check if today's backup exists
if ! ls ${BACKUP_DIR}/postgres_${TODAY}_*.sql >/dev/null 2>&1; then
    echo "WARNING: No backup found for today ($TODAY)"
    exit 1
fi

# Check backup file sizes
LATEST_BACKUP=$(ls ${BACKUP_DIR}/postgres_${TODAY}_*.sql | tail -1)
BACKUP_SIZE=$(stat -c%s "$LATEST_BACKUP")

if [ $BACKUP_SIZE -lt 1000000 ]; then # Less than 1MB
    echo "WARNING: Backup file seems too small: $BACKUP_SIZE bytes"
    exit 1
fi

echo "Backup check passed for $TODAY"
```

## Operations Guide

### Service Management

#### Basic Operations
```bash
# Check service status
docker compose ps

# View logs for all services
docker compose logs -f

# View logs for specific service
docker compose logs -f n8n
docker compose logs -f postgres
docker compose logs -f traefik
docker compose logs -f backup

# Restart specific service
docker compose restart n8n

# Stop all services
docker compose down

# Start all services
docker compose up -d

# Update services to latest images
docker compose pull
docker compose up -d
```

#### Service Health Checks
```bash
# Check n8n accessibility
curl -k -I https://n8n.${DOMAIN_NAME:-localhost}

# Check PostgreSQL connection
docker compose exec postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}"

# Check container resource usage
docker stats

# Check disk usage
df -h
du -sh ./backups
```

### Database Operations

#### PostgreSQL Management
```bash
# Connect to PostgreSQL as admin
docker compose exec postgres psql -U postgres -d n8n

# Connect as n8n application user
docker compose exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}"

# View database size and tables
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public' 
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# Check active connections
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT pid, usename, application_name, client_addr, state, query_start 
FROM pg_stat_activity 
WHERE datname = 'n8n';"
```

#### Database Maintenance
```bash
# Analyze database performance
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT schemaname, tablename, attname, n_distinct, correlation 
FROM pg_stats 
WHERE tablename LIKE '%execution%' 
ORDER BY tablename, attname;"

# Vacuum and analyze (maintenance)
docker compose exec postgres psql -U postgres -d n8n -c "VACUUM ANALYZE;"

# Check database locks
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.usename AS blocked_user,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.usename AS blocking_user,
       blocked_activity.query AS blocked_statement,
       blocking_activity.query AS current_statement_in_blocking_process
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks ON blocking_locks.locktype = blocked_locks.locktype
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;"
```

### Environment Management

#### Environment Variables
```bash
# View current environment configuration (excluding passwords)
grep -v PASSWORD .env

# Update environment variables
# 1. Edit .env file
nano .env

# 2. Recreate services with new configuration
docker compose up -d --force-recreate

# 3. Verify changes
docker compose config
```

#### SSL Certificate Management
```bash
# Check certificate status
docker compose exec traefik ls -la /letsencrypt/

# View certificate expiration
openssl x509 -in config/dynamic/localhost.crt -text -noout | grep -A2 "Validity"

# Force certificate renewal (for Let's Encrypt)
docker compose restart traefik

# Generate new self-signed certificates
rm -f config/dynamic/localhost.*
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout config/dynamic/localhost.key \
    -out config/dynamic/localhost.crt \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:n8n.localhost,IP:127.0.0.1"
```

### Performance Monitoring

#### Resource Usage
```bash
# Monitor container resources
docker stats --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"

# Check volume sizes
docker system df -v

# Monitor n8n workflow executions
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT 
    DATE(\"startedAt\") as execution_date,
    COUNT(*) as total_executions,
    COUNT(CASE WHEN finished = true THEN 1 END) as completed,
    COUNT(CASE WHEN \"stoppedAt\" IS NOT NULL AND finished = false THEN 1 END) as failed
FROM execution_entity 
WHERE \"startedAt\" > NOW() - INTERVAL '7 days'
GROUP BY DATE(\"startedAt\")
ORDER BY execution_date DESC;"
```

#### Log Analysis
```bash
# Find errors in n8n logs
docker compose logs n8n 2>&1 | grep -i error | tail -20

# Monitor PostgreSQL slow queries (if enabled)
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT query, calls, total_time, mean_time, rows
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;"

# Check disk I/O performance
iostat -x 1 5  # Requires sysstat package
```

## Troubleshooting

### Common Issues and Solutions

#### 1. n8n Cannot Connect to Database
**Symptoms:**
- n8n container restarts repeatedly
- Database connection errors in logs
- "Connection refused" errors

**Diagnosis:**
```bash
# Check PostgreSQL logs
docker compose logs postgres | tail -50

# Test database connectivity
docker compose exec postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}"

# Check if PostgreSQL is accepting connections
docker compose exec n8n nc -zv postgres 5432
```

**Solutions:**
```bash
# 1. Verify database credentials in .env file
grep -E "POSTGRES_.*=" .env

# 2. Check PostgreSQL service health
docker compose ps postgres

# 3. Restart PostgreSQL service
docker compose restart postgres

# 4. If database is corrupted, restore from backup
./restore.sh YYYYMMDD_HHMMSS

# 5. Reset database (WARNING: This will delete all data)
docker compose down
docker volume rm compose_postgres_data
docker compose up -d
```

#### 2. SSL Certificate Issues
**Symptoms:**
- Browser security warnings
- "SSL_ERROR_SELF_SIGNED_CERT" errors
- Traefik certificate errors

**Diagnosis:**
```bash
# Check certificate files
ls -la config/dynamic/

# Test SSL connection
openssl s_client -connect localhost:443 -servername n8n.localhost

# Check Traefik logs for certificate errors
docker compose logs traefik | grep -i cert
```

**Solutions:**
```bash
# 1. Regenerate self-signed certificates
rm -f config/dynamic/localhost.*
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout config/dynamic/localhost.key \
    -out config/dynamic/localhost.crt \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:n8n.localhost,IP:127.0.0.1"

# 2. Restart Traefik
docker compose restart traefik

# 3. For production, ensure DNS points to your server
# and update DOMAIN_NAME in .env file

# 4. Check browser certificate acceptance
# Add exception for self-signed certificates in browser
```

#### 3. Backup Service Not Working
**Symptoms:**
- No recent backup files
- Backup container not running
- Cron job failures

**Diagnosis:**
```bash
# Check backup service status
docker compose ps backup

# View backup service logs
docker compose logs backup

# Check if backup files are being created
ls -la ./backups/ | head -10

# Test backup script manually
./backup-manual.sh
```

**Solutions:**
```bash
# 1. Restart backup service
docker compose restart backup

# 2. Check cron configuration in backup container
docker compose exec backup crontab -l

# 3. Run backup manually to test
docker compose exec backup /app/backup.sh

# 4. Check disk space for backups
df -h .
du -sh ./backups

# 5. Fix permissions if needed
chmod +x backup.sh backup-manual.sh restore.sh
```

#### 4. Performance Issues
**Symptoms:**
- Slow workflow execution
- High memory usage
- Database timeouts
- Browser timeouts

**Diagnosis:**
```bash
# Check resource usage
docker stats

# Monitor system resources
top
free -h
df -h

# Check PostgreSQL performance
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '1 minute';"
```

**Solutions:**
```bash
# 1. Optimize PostgreSQL
docker compose exec postgres psql -U postgres -d n8n -c "VACUUM ANALYZE;"

# 2. Clean up old executions
docker compose exec postgres psql -U postgres -d n8n -c "
DELETE FROM execution_entity 
WHERE \"startedAt\" < NOW() - INTERVAL '30 days'
AND finished = true;"

# 3. Restart services to clear memory
docker compose restart

# 4. Increase resource limits in docker-compose.yml
# Add under each service:
# deploy:
#   resources:
#     limits:
#       memory: 2G
#       cpus: '1.5'

# 5. Monitor and optimize workflows
# Check n8n executions tab for slow workflows
```

#### 5. Data Loss or Corruption
**Symptoms:**
- Workflows disappear
- Credentials missing
- Database errors
- Volume mount issues

**Diagnosis:**
```bash
# Check data volumes
docker volume ls | grep compose

# Inspect volume contents
docker run --rm -v compose_n8n_data:/data alpine ls -la /data

# Check database integrity
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT pg_database_size('n8n') as db_size;"
```

**Solutions:**
```bash
# 1. Restore from latest backup
./restore.sh $(ls ./backups/backup_info_*.txt | sed 's/.*backup_info_\(.*\)\.txt/\1/' | sort -r | head -1)

# 2. If no backup available, check volume backup
ls -la ./backups/n8n_data_*.tar.gz | tail -1

# 3. Rebuild from clean state (last resort)
docker compose down -v  # WARNING: This deletes all data
docker compose up -d

# 4. Prevent future data loss
# - Set up regular backup monitoring
# - Test restore procedures monthly
# - Consider off-site backup storage
```

### Debugging Tools

#### Container Inspection
```bash
# Enter container shells for debugging
docker compose exec n8n /bin/sh
docker compose exec postgres /bin/bash
docker compose exec traefik /bin/sh

# Check container configurations
docker compose config

# Inspect running containers
docker inspect compose_n8n_1
docker inspect compose_postgres_1
```

#### Network Debugging
```bash
# Test internal network connectivity
docker compose exec n8n ping postgres
docker compose exec n8n nc -zv postgres 5432

# Check external connectivity
curl -k -v https://n8n.taurak.co.uk
curl -v http://localhost:8081  # Traefik dashboard

# List network configuration
docker network ls
docker network inspect compose_default
```

#### Log Collection
```bash
# Collect all logs for support
docker compose logs --no-color > system_logs_$(date +%Y%m%d_%H%M%S).log

# Real-time log monitoring
docker compose logs -f --tail=100

# Filter logs by severity
docker compose logs 2>&1 | grep -i "error\|warn\|fatal"
```

## Security Considerations

### Container Security
- ✅ **Non-root execution**: n8n runs as user 1000:1000, PostgreSQL as 999:999
- ✅ **Minimal attack surface**: Alpine-based images where possible
- ✅ **No privileged containers**: All containers run without elevated privileges
- ✅ **Read-only filesystems**: Critical paths are read-only where feasible

### Network Security
- ✅ **Internal network isolation**: Services communicate via private Docker network
- ✅ **No direct database access**: PostgreSQL is not exposed externally
- ✅ **SSL/TLS encryption**: All external traffic encrypted via Traefik
- ✅ **Secure defaults**: HTTP automatically redirects to HTTPS

### Authentication & Access Control
- ✅ **Basic authentication**: n8n protected with username/password
- ✅ **Database user separation**: Dedicated non-admin user for n8n application
- ✅ **Environment-based secrets**: Credentials stored in environment variables
- ✅ **Principle of least privilege**: Each service has minimal required permissions

### Data Protection
- ✅ **Automated backups**: Daily backups with 30-day retention
- ✅ **Data persistence**: All critical data stored in Docker volumes
- ✅ **Backup encryption**: Consider encrypting backups for sensitive environments
- ✅ **Access logging**: Traefik logs all access attempts

### Security Best Practices

#### Credential Management
```bash
# Use strong, unique passwords
POSTGRES_PASSWORD=$(openssl rand -base64 32)
N8N_BASIC_AUTH_PASSWORD=$(openssl rand -base64 32)

# Store in .env file (never commit to version control)
echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}" >> .env
echo "N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}" >> .env

# Regular credential rotation (quarterly recommended)
./scripts/rotate-credentials.sh
```

#### File Permissions
```bash
# Secure configuration files
chmod 600 .env
chmod 600 config/dynamic/*.key
chmod 644 config/dynamic/*.crt

# Secure backup files
chmod 700 ./backups
find ./backups -type f -exec chmod 600 {} \;
```

#### Network Hardening
```bash
# Firewall configuration (example for UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw --force enable

# Monitor network connections
ss -tulpn | grep -E ":80|:443|:5432|:5678"
```

## Advanced Configuration

### Production Deployment

#### Domain Setup
For production deployment with a real domain:

```bash
# 1. Update DNS records
# Point your domain to your server IP:
# n8n.taurak.co.uk -> YOUR_SERVER_IP

# 2. Update environment variables
cat >> .env << EOF
DOMAIN_NAME=taurak.co.uk
SUBDOMAIN=n8n
SSL_EMAIL=admin@taurak.co.uk
EOF

# 3. Let's Encrypt will automatically obtain SSL certificates
docker compose up -d
```

#### High Availability Setup
For production environments requiring redundancy:

```yaml
# docker-compose.ha.yml (example for load balancing)
version: '3.8'
services:
  n8n-1:
    image: docker.n8n.io/n8nio/n8n
    # ... same configuration as n8n service
    
  n8n-2:
    image: docker.n8n.io/n8nio/n8n
    # ... same configuration as n8n service
    
  postgres-primary:
    image: postgres:16
    # Primary database configuration
    
  postgres-replica:
    image: postgres:16
    # Read replica configuration
```

#### External Database
To use an external PostgreSQL instance:

```bash
# Update .env for external database
cat >> .env << EOF
# External PostgreSQL configuration
DB_POSTGRESDB_HOST=external-postgres.company.com
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_SSL_ENABLED=true
EOF

# Remove postgres service from docker-compose.yml
# Update n8n depends_on to remove postgres dependency
```

### Monitoring Integration

#### Prometheus Metrics
```yaml
# Add to docker-compose.yml for monitoring
prometheus:
  image: prom/prometheus
  ports:
    - "9090:9090"
  volumes:
    - ./config/prometheus.yml:/etc/prometheus/prometheus.yml

grafana:
  image: grafana/grafana
  ports:
    - "3000:3000"
  environment:
    - GF_SECURITY_ADMIN_PASSWORD=admin
```

#### Health Check Endpoint
```bash
# Add health check monitoring
curl -f https://n8n.taurak.co.uk/healthz || exit 1

# Set up monitoring cron job
echo "*/5 * * * * /path/to/health-check.sh" | crontab -
```

## Maintenance

### Regular Maintenance Tasks

#### Weekly Tasks
```bash
#!/bin/bash
# weekly-maintenance.sh

# Update container images
docker compose pull

# Clean up unused Docker resources
docker system prune -f

# Optimize database
docker compose exec postgres psql -U postgres -d n8n -c "VACUUM ANALYZE;"

# Check backup integrity
./scripts/verify-backups.sh

# Review logs for errors
docker compose logs --since 168h 2>&1 | grep -i error > weekly_errors.log
```

#### Monthly Tasks
```bash
#!/bin/bash
# monthly-maintenance.sh

# Test restore procedure
LATEST_BACKUP=$(ls ./backups/backup_info_*.txt | tail -1 | sed 's/.*backup_info_\(.*\)\.txt/\1/')
echo "Testing restore of backup: $LATEST_BACKUP"
# ./restore.sh $LATEST_BACKUP --dry-run

# Rotate credentials
./scripts/rotate-credentials.sh

# Security scan
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy image n8nio/n8n

# Performance review
docker compose exec postgres psql -U postgres -d n8n -c "
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC LIMIT 10;"
```

### Upgrading

#### n8n Version Upgrades
```bash
# 1. Create backup before upgrade
./backup-manual.sh

# 2. Check for breaking changes in n8n release notes
# https://github.com/n8n-io/n8n/releases

# 3. Update to latest version
docker compose pull n8n
docker compose up -d n8n

# 4. Verify functionality
curl -k https://n8n.taurak.co.uk/healthz

# 5. Check logs for any issues
docker compose logs n8n | tail -50
```

#### PostgreSQL Version Upgrades
```bash
# Major PostgreSQL upgrades require data migration
# 1. Full backup
./backup-manual.sh

# 2. Export data
docker compose exec postgres pg_dumpall -U postgres > full_backup.sql

# 3. Stop services and update image version
docker compose down
# Edit docker-compose.yml to new PostgreSQL version
docker compose up -d postgres

# 4. Import data if needed
# docker compose exec -T postgres psql -U postgres < full_backup.sql
```

## Support and Documentation

### Getting Help

#### Community Resources
- **n8n Community**: https://community.n8n.io/
- **n8n Documentation**: https://docs.n8n.io/
- **Docker Documentation**: https://docs.docker.com/
- **PostgreSQL Documentation**: https://www.postgresql.org/docs/

#### Log Collection for Support
```bash
# Collect comprehensive system information
./scripts/collect-support-info.sh

# This creates a support bundle with:
# - Service configurations
# - Recent logs  
# - System information
# - Error reports
# - Performance metrics
```

#### Issue Reporting Template
When reporting issues, include:

1. **Environment Information**:
   ```bash
   docker --version
   docker compose version
   uname -a
   ```

2. **Service Status**:
   ```bash
   docker compose ps
   docker compose config --quiet && echo "Config valid" || echo "Config invalid"
   ```

3. **Recent Logs**:
   ```bash
   docker compose logs --tail=100 service_name
   ```

4. **Error Details**: Specific error messages and reproduction steps

### Configuration Reference

#### Environment Variables Reference
| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `DOMAIN_NAME` | Base domain for services | `localhost` | Yes |
| `SUBDOMAIN` | n8n subdomain | `n8n` | Yes |
| `SSL_EMAIL` | Email for SSL certificates | - | Yes |
| `POSTGRES_DB` | PostgreSQL database name | `n8n` | Yes |
| `POSTGRES_USER` | PostgreSQL admin user | `postgres` | Yes |
| `POSTGRES_PASSWORD` | PostgreSQL admin password | - | Yes |
| `N8N_BASIC_AUTH_USER` | n8n admin username | `admin` | Yes |
| `N8N_BASIC_AUTH_PASSWORD` | n8n admin password | - | Yes |
| `GENERIC_TIMEZONE` | System timezone | `UTC` | No |
| `N8N_RUNNERS_ENABLED` | Enable n8n runners | `true` | No |

#### Port Mapping Reference
| Service | Internal Port | External Port | Description |
|---------|---------------|---------------|-------------|
| Traefik | 80 | 8080 | HTTP (redirects to HTTPS) |
| Traefik | 443 | 8443 | HTTPS |
| Traefik | 8080 | 8081 | Dashboard |
| n8n | 5678 | - | Web interface (via Traefik) |
| PostgreSQL | 5432 | - | Database (internal only) |

---

This Docker Compose setup provides a robust, production-ready n8n installation with comprehensive backup and restore capabilities. The automated backup system ensures your workflow data is protected, while the security configurations follow best practices for container deployment.

For questions or issues, refer to the troubleshooting section above or consult the n8n community resources.
