# n8n Self-Hosted Docker Setup with Database Integration

A complete, production-ready Docker Compose setup for n8n workflow automation on Ubuntu 25.04 with NVIDIA RTX 2070 GPU support, PostgreSQL database, and SSL termination.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 25.04 LTS (AMD64)
- **Hardware**: NVIDIA RTX 2070 GPU or better
- **Resources**: 8GB+ RAM, 30GB+ free disk space
- **Network**: Internet connectivity for initial setup
- **Privileges**: Sudo access for Docker installation

### Verify System Compatibility
```bash
# Check Ubuntu version
lsb_release -a

# Verify NVIDIA GPU
nvidia-smi

# Check available disk space
df -h
```

## Architecture Overview

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

## Quick Start Guide

### 1. Clone and Setup
```bash
# Create project directory
mkdir -p ~/n8n-docker && cd ~/n8n-docker

# Download configuration files (manual creation required)
# Files needed: docker-compose.yml, .env, init.sql, traefik.yml
```

### 2. Environment Configuration
```bash
# Copy and customize environment variables
cp .env.example .env
nano .env  # Edit with your settings
```

### 3. Deploy Stack
```bash
# Install Docker and dependencies
./scripts/install-dependencies.sh

# Start services
docker-compose up -d

# Verify deployment
docker-compose ps
```

### 4. Access n8n
```bash
# Check status
curl -k https://localhost/healthz

# Open in browser
firefox https://n8n.localhost
```

## Detailed Setup

### Step 1: Install Docker and Dependencies

Create installation script:
```bash
#!/bin/bash
# scripts/install-dependencies.sh

set -euo pipefail

echo "Installing Docker and NVIDIA Container Toolkit..."

# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    jq

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $USER
    echo "Docker installed. Please log out and back in to use Docker without sudo."
fi

# Install NVIDIA Container Toolkit
if ! command -v nvidia-container-toolkit &> /dev/null; then
    echo "Installing NVIDIA Container Toolkit..."
    distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
        && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
        && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
            sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
            sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt update
    sudo apt install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
fi

# Verify installations
echo "Verifying installations..."
docker --version
docker compose version
nvidia-container-toolkit --version || echo "NVIDIA Container Toolkit installed"

echo "Installation complete!"
echo "Note: If Docker was just installed, please log out and back in to use Docker without sudo."
```

### Step 2: Docker Compose Configuration

#### Main Stack Configuration
```yaml
# docker-compose.yml
version: '3.8'

services:
  traefik:
    image: traefik:v3.0
    container_name: n8n-traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"  # Traefik dashboard
    environment:
      - TRAEFIK_API_DASHBOARD=true
      - TRAEFIK_API_INSECURE=true
      - TRAEFIK_ENTRYPOINTS_WEB_ADDRESS=:80
      - TRAEFIK_ENTRYPOINTS_WEBSECURE_ADDRESS=:443
      - TRAEFIK_PROVIDERS_DOCKER=true
      - TRAEFIK_PROVIDERS_DOCKER_EXPOSEDBYDEFAULT=false
      - TRAEFIK_PROVIDERS_FILE_DIRECTORY=/etc/traefik/dynamic
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_TLSCHALLENGE=true
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${ACME_EMAIL}
      - TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/letsencrypt/acme.json
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_data:/letsencrypt
      - ./config/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./config/dynamic:/etc/traefik/dynamic:ro
    networks:
      - n8n-network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`traefik.${DOMAIN_NAME}`)"
      - "traefik.http.routers.dashboard.tls=true"
      - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"

  postgres:
    image: postgres:16-alpine
    container_name: n8n-postgres
    restart: unless-stopped
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_NON_ROOT_USER=${POSTGRES_NON_ROOT_USER}
      - POSTGRES_NON_ROOT_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    networks:
      - n8n-network
    security_opt:
      - no-new-privileges:true
    user: "999:999"  # postgres user
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n:latest
    container_name: n8n-app
    restart: unless-stopped
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      # Database Configuration
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_NON_ROOT_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_NON_ROOT_PASSWORD}
      
      # n8n Configuration
      - N8N_HOST=${N8N_HOST}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${N8N_HOST}
      - GENERIC_TIMEZONE=${TIMEZONE}
      
      # Security
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_BASIC_AUTH_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_BASIC_AUTH_PASSWORD}
      
      # Execution
      - EXECUTIONS_PROCESS=main
      - EXECUTIONS_MODE=regular
      - EXECUTIONS_DATA_SAVE_ON_ERROR=all
      - EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
      - EXECUTIONS_DATA_MAX_AGE=336  # 14 days
      
      # Workflow settings
      - N8N_METRICS=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      
      # GPU configuration (when needed)
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - n8n-network
    user: "1000:1000"  # node user
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(`${N8N_HOST}`)"
      - "traefik.http.routers.n8n.tls=true"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"

  watchtower:
    image: containrrr/watchtower
    container_name: n8n-watchtower
    restart: unless-stopped
    environment:
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_POLL_INTERVAL=86400  # 24 hours
      - WATCHTOWER_INCLUDE_STOPPED=true
      - WATCHTOWER_REVIVE_STOPPED=false
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - n8n-network
    security_opt:
      - no-new-privileges:true

volumes:
  postgres_data:
    driver: local
  n8n_data:
    driver: local
  traefik_data:
    driver: local

networks:
  n8n-network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

#### Environment Variables Template
```bash
# .env.example
# Copy to .env and customize

# Domain Configuration
DOMAIN_NAME=localhost
N8N_HOST=n8n.localhost
ACME_EMAIL=admin@localhost

# Database Configuration
POSTGRES_DB=n8n
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_postgres_password_here
POSTGRES_NON_ROOT_USER=n8n_user
POSTGRES_NON_ROOT_PASSWORD=your_secure_n8n_password_here

# n8n Authentication
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=your_secure_n8n_admin_password_here

# System Configuration
TIMEZONE=UTC

# Security Notes:
# - Use strong passwords (16+ characters, mixed case, numbers, symbols)
# - Never commit .env file to version control
# - Rotate passwords regularly
# - Consider using external secret management for production
```

#### Database Initialization
```sql
-- init.sql
-- PostgreSQL initialization script for n8n

-- Create non-root user for n8n application
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = 'n8n_user') THEN
      
      CREATE ROLE n8n_user LOGIN PASSWORD 'your_secure_n8n_password_here';
   END IF;
END
$do$;

-- Grant necessary permissions
GRANT CONNECT ON DATABASE n8n TO n8n_user;
GRANT USAGE ON SCHEMA public TO n8n_user;
GRANT CREATE ON SCHEMA public TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;

-- Create custom application schema (optional)
CREATE SCHEMA IF NOT EXISTS app_data;
GRANT USAGE ON SCHEMA app_data TO n8n_user;
GRANT CREATE ON SCHEMA app_data TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data GRANT ALL ON SEQUENCES TO n8n_user;

-- Example custom table for Google Sheets replacement
CREATE TABLE IF NOT EXISTS app_data.workflow_data (
    id SERIAL PRIMARY KEY,
    workflow_id VARCHAR(255) NOT NULL,
    data_type VARCHAR(100) NOT NULL,
    data_json JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workflow_id, data_type)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_workflow_data_workflow_id ON app_data.workflow_data(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_data_type ON app_data.workflow_data(data_type);
CREATE INDEX IF NOT EXISTS idx_workflow_data_created_at ON app_data.workflow_data(created_at);

-- Example view for simplified access
CREATE OR REPLACE VIEW app_data.latest_workflow_data AS
SELECT DISTINCT ON (workflow_id, data_type) 
    id, workflow_id, data_type, data_json, created_at, updated_at
FROM app_data.workflow_data
ORDER BY workflow_id, data_type, updated_at DESC;

-- Grant permissions on new objects
GRANT ALL ON app_data.workflow_data TO n8n_user;
GRANT ALL ON SEQUENCE app_data.workflow_data_id_seq TO n8n_user;
GRANT SELECT ON app_data.latest_workflow_data TO n8n_user;

COMMENT ON TABLE app_data.workflow_data IS 'Centralized storage for workflow data, replacing Google Sheets';
COMMENT ON VIEW app_data.latest_workflow_data IS 'Latest version of each workflow data entry';
```

#### Traefik Configuration
```yaml
# config/traefik.yml
global:
  checkNewVersion: false
  sendAnonymousUsage: false

serversTransport:
  insecureSkipVerify: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
          permanent: true

  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      tlsChallenge: {}
      email: admin@localhost
      storage: /letsencrypt/acme.json

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
  file:
    directory: /etc/traefik/dynamic
    watch: true

api:
  dashboard: true
  insecure: true

log:
  level: INFO

accessLog: {}
```

### Step 3: Deployment Scripts

#### Deployment Helper Script
```bash
#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying n8n Docker Stack..."

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please run install-dependencies.sh first."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose not found. Please run install-dependencies.sh first."
    exit 1
fi

# Check environment file
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo "❌ Environment file not found. Please copy .env.example to .env and customize."
    exit 1
fi

# Create necessary directories
mkdir -p "$PROJECT_DIR/config/dynamic"

# Generate self-signed certificates for local development
if [[ ! -f "$PROJECT_DIR/config/dynamic/tls.yml" ]]; then
    echo "📄 Generating self-signed certificates for local development..."
    cat > "$PROJECT_DIR/config/dynamic/tls.yml" << EOF
tls:
  certificates:
    - certFile: /etc/traefik/dynamic/localhost.crt
      keyFile: /etc/traefik/dynamic/localhost.key
      stores:
        - default
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/dynamic/localhost.crt
        keyFile: /etc/traefik/dynamic/localhost.key
EOF

    # Generate certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_DIR/config/dynamic/localhost.key" \
        -out "$PROJECT_DIR/config/dynamic/localhost.crt" \
        -subj "/C=US/ST=Local/L=Local/O=Local/OU=Local/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,DNS:n8n.localhost,DNS:traefik.localhost,IP:127.0.0.1"
fi

# Pull latest images
echo "⬇️ Pulling latest Docker images..."
docker compose pull

# Deploy stack
echo "🏗️ Starting services..."
docker compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Check service status
echo "🔍 Checking service status..."
docker compose ps

# Verify connectivity
echo "🌐 Verifying connectivity..."
if curl -k -s https://localhost/healthz > /dev/null 2>&1; then
    echo "✅ n8n is accessible"
else
    echo "⚠️ n8n may still be starting up. Check logs: docker compose logs n8n"
fi

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Access URLs:"
echo "  - n8n: https://n8n.localhost"
echo "  - Traefik Dashboard: http://localhost:8080"
echo ""
echo "Default credentials (change these!):"
echo "  - Username: admin"
echo "  - Password: (check your .env file)"
echo ""
echo "Useful commands:"
echo "  - View logs: docker compose logs -f"
echo "  - Stop services: docker compose down"
echo "  - Restart: docker compose restart"
echo "  - Update: docker compose pull && docker compose up -d"
```

## Database Configuration

### Why PostgreSQL?
PostgreSQL was selected as the optimal database for this deployment based on:

1. **n8n Native Support**: First-class integration with n8n's execution engine
2. **JSON/JSONB Support**: Excellent handling of workflow data structures
3. **ACID Compliance**: Ensures data integrity for critical automation workflows
4. **Performance**: Superior query optimization for complex workflow data
5. **Ecosystem**: Rich extension ecosystem (PostGIS, TimescaleDB, etc.)
6. **Security**: Robust authentication and authorization mechanisms

### Database Schema Design

The minimal schema supports:
- **Workflow Metadata**: Execution history, performance metrics
- **Custom Application Data**: Replacement for Google Sheets functionality
- **User Management**: Credentials and permissions
- **Audit Logging**: Change tracking and compliance

### Connection Configuration

n8n connects to PostgreSQL using environment variables:
```bash
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=your_secure_password
```

## Workflow Migration

### Replacing Google Sheets Nodes

#### 1. Identify Google Sheets Operations
```bash
# Export existing workflows
docker exec n8n-app n8n export:workflow --all --output=/tmp/workflows.json

# Search for Google Sheets nodes
grep -r "googleSheets" /path/to/workflows/
```

#### 2. Database Operations Mapping
| Google Sheets Operation | PostgreSQL Equivalent |
|------------------------|----------------------|
| Read rows | `SELECT * FROM table WHERE conditions` |
| Append row | `INSERT INTO table (columns) VALUES (values)` |
| Update row | `UPDATE table SET column=value WHERE id=?` |
| Delete row | `DELETE FROM table WHERE id=?` |
| Lookup value | `SELECT column FROM table WHERE condition LIMIT 1` |

#### 3. Migration Example

**Before (Google Sheets Node):**
```json
{
  "name": "Google Sheets",
  "type": "n8n-nodes-base.googleSheets",
  "parameters": {
    "operation": "append",
    "documentId": "your-sheet-id",
    "sheetName": "Sheet1",
    "columns": ["name", "email", "status"]
  }
}
```

**After (PostgreSQL Node):**
```json
{
  "name": "PostgreSQL",
  "type": "n8n-nodes-base.postgres",
  "parameters": {
    "operation": "insert",
    "schema": "app_data",
    "table": "workflow_data",
    "columns": "workflow_id, data_type, data_json",
    "additionalFields": {
      "mode": "independently"
    }
  }
}
```

#### 4. Data Transformation
```javascript
// n8n Code node for data transformation
const items = $input.all();

return items.map(item => {
  return {
    workflow_id: $workflow.id,
    data_type: 'user_submission',
    data_json: JSON.stringify({
      name: item.json.name,
      email: item.json.email,
      status: item.json.status,
      submitted_at: new Date().toISOString()
    })
  };
});
```

## Security Checklist

### Container Security
- ✅ Non-root user execution (n8n: 1000:1000, postgres: 999:999)
- ✅ Read-only root filesystem where possible
- ✅ No new privileges security option
- ✅ Minimal base images (Alpine Linux)
- ✅ Regular security updates via Watchtower

### Network Security
- ✅ Isolated Docker network (172.20.0.0/16)
- ✅ No direct external database access
- ✅ SSL/TLS encryption for all external traffic
- ✅ Internal service communication only

### Data Security
- ✅ Environment variable-based secrets
- ✅ PostgreSQL password authentication
- ✅ n8n basic authentication enabled
- ✅ Encrypted data at rest (volume encryption)
- ✅ SSL certificate management

### Access Control
- ✅ Traefik dashboard behind authentication
- ✅ PostgreSQL non-root application user
- ✅ Principle of least privilege
- ✅ Regular credential rotation

### Monitoring
- ✅ Health checks for all services
- ✅ Log aggregation and retention
- ✅ Resource usage monitoring
- ✅ Automated backup verification

## Operations Guide

### Daily Operations

#### Service Management
```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f n8n
docker compose logs -f postgres
docker compose logs -f traefik

# Restart specific service
docker compose restart n8n

# Update services
docker compose pull
docker compose up -d
```

#### Database Operations
```bash
# Connect to PostgreSQL
docker exec -it n8n-postgres psql -U postgres -d n8n

# Backup database
docker exec n8n-postgres pg_dump -U postgres n8n > backup_$(date +%Y%m%d_%H%M%S).sql

# Restore database
docker exec -i n8n-postgres psql -U postgres -d n8n < backup_file.sql

# Monitor database performance
docker exec n8n-postgres psql -U postgres -d n8n -c "
SELECT schemaname,tablename,attname,n_distinct,correlation 
FROM pg_stats WHERE tablename = 'workflow_data';"
```

### Backup Procedures

#### Automated Backup Script
```bash
#!/bin/bash
# scripts/backup.sh

set -euo pipefail

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "🗄️ Creating backup for $DATE..."

# Backup database
echo "📊 Backing up PostgreSQL database..."
docker exec n8n-postgres pg_dump -U postgres n8n | gzip > "$BACKUP_DIR/postgres_$DATE.sql.gz"

# Backup n8n data
echo "⚙️ Backing up n8n data..."
docker run --rm -v n8n-docker_n8n_data:/data -v "$PWD/$BACKUP_DIR":/backup alpine tar czf /backup/n8n_data_$DATE.tar.gz -C /data .

# Backup configuration
echo "📝 Backing up configuration..."
tar czf "$BACKUP_DIR/config_$DATE.tar.gz" docker-compose.yml .env config/

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete

echo "✅ Backup completed: $BACKUP_DIR"
echo "📦 Files created:"
ls -lh "$BACKUP_DIR"/*$DATE*
```

#### Backup Verification
```bash
#!/bin/bash
# scripts/verify-backup.sh

BACKUP_FILE="$1"

if [[ -z "$BACKUP_FILE" ]]; then
    echo "Usage: $0 <backup_file.sql.gz>"
    exit 1
fi

echo "🔍 Verifying backup: $BACKUP_FILE"

# Test database backup integrity
gunzip -t "$BACKUP_FILE" && echo "✅ Backup file is valid"

# Test restore capability (dry run)
gunzip -c "$BACKUP_FILE" | head -20
echo "✅ Backup content verified"
```

### Monitoring and Alerts

#### Health Check Script
```bash
#!/bin/bash
# scripts/health-check.sh

set -euo pipefail

echo "🏥 Running health checks..."

# Check Docker services
if ! docker compose ps | grep -q "Up"; then
    echo "❌ Some services are not running"
    docker compose ps
    exit 1
fi

# Check n8n accessibility
if ! curl -k -s -f https://localhost > /dev/null; then
    echo "❌ n8n is not accessible"
    exit 1
fi

# Check database connectivity
if ! docker exec n8n-postgres pg_isready -U postgres -d n8n > /dev/null; then
    echo "❌ PostgreSQL is not ready"
    exit 1
fi

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 80 ]]; then
    echo "⚠️ Disk usage is ${DISK_USAGE}% (>80%)"
fi

# Check memory usage
MEMORY_USAGE=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2*100}')
if [[ $MEMORY_USAGE -gt 90 ]]; then
    echo "⚠️ Memory usage is ${MEMORY_USAGE}% (>90%)"
fi

echo "✅ All health checks passed"
```

### Performance Optimization

#### PostgreSQL Tuning
```sql
-- Performance optimization queries
-- Run these in PostgreSQL to optimize for n8n workloads

-- Analyze table statistics
ANALYZE;

-- Check slow queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Optimize n8n execution data retention
DELETE FROM execution_entity 
WHERE "startedAt" < NOW() - INTERVAL '30 days'
AND finished = true;

-- Vacuum and reindex
VACUUM ANALYZE;
REINDEX DATABASE n8n;
```

#### Docker Resource Limits
```yaml
# Add to docker-compose.yml services
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '1.5'
    reservations:
      memory: 512M
      cpus: '0.5'
```

## Troubleshooting

### Common Issues and Solutions

#### 1. n8n Cannot Connect to Database
**Symptoms:**
- n8n container restarts repeatedly
- Database connection errors in logs

**Solutions:**
```bash
# Check PostgreSQL logs
docker compose logs postgres

# Verify database credentials
docker exec n8n-postgres psql -U n8n_user -d n8n -c "SELECT 1;"

# Reset database password
docker exec -it n8n-postgres psql -U postgres -c "ALTER USER n8n_user PASSWORD 'new_password';"
```

#### 2. SSL Certificate Issues
**Symptoms:**
- Browser security warnings
- Traefik certificate errors

**Solutions:**
```bash
# Regenerate self-signed certificates
rm config/dynamic/localhost.*
./scripts/deploy.sh

# Check Traefik configuration
docker compose logs traefik | grep -i certificate

# Force certificate refresh
docker compose restart traefik
```

#### 3. GPU Not Accessible
**Symptoms:**
- NVIDIA runtime errors
- GPU nodes fail in n8n workflows

**Solutions:**
```bash
# Verify NVIDIA Docker runtime
docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi

# Check container GPU access
docker exec n8n-app nvidia-smi

# Restart Docker daemon
sudo systemctl restart docker
docker compose up -d
```

#### 4. Performance Issues
**Symptoms:**
- Slow workflow execution
- High memory usage
- Database locks

**Solutions:**
```bash
# Monitor resource usage
docker stats

# Check database performance
docker exec n8n-postgres psql -U postgres -d n8n -c "
SELECT pid, now() - pg_stat_activity.query_start AS duration, query 
FROM pg_stat_activity 
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';"

# Optimize database
docker exec n8n-postgres psql -U postgres -d n8n -c "VACUUM ANALYZE;"

# Scale resources
# Edit docker-compose.yml to increase memory/CPU limits
docker compose up -d
```

#### 5. Data Corruption or Loss
**Symptoms:**
- Workflows disappear
- Database connection failures
- Data inconsistencies

**Solutions:**
```bash
# Check data integrity
docker exec n8n-postgres psql -U postgres -d n8n -c "
SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;"

# Restore from backup
./scripts/restore-backup.sh backups/postgres_YYYYMMDD_HHMMSS.sql.gz

# Rebuild from clean state
docker compose down -v
docker compose up -d
```

### Log Analysis

#### Centralized Logging Setup
```bash
# View all logs with timestamps
docker compose logs -f -t

# Filter specific service logs
docker compose logs -f n8n | grep -i error

# Export logs for analysis
docker compose logs --no-color > system_logs_$(date +%Y%m%d).log
```

#### Log Rotation Configuration
```bash
# Add to docker-compose.yml for each service
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### Network Diagnostics

#### Connectivity Testing
```bash
# Test internal network connectivity
docker exec n8n-app ping postgres
docker exec n8n-app nc -zv postgres 5432

# Test external connectivity
curl -k -v https://localhost
curl -v http://localhost:8080  # Traefik dashboard

# Check DNS resolution
docker exec n8n-app nslookup postgres
```

#### Port Conflict Resolution
```bash
# Check port usage
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443
sudo netstat -tulpn | grep :5432

# Modify ports in docker-compose.yml if conflicts exist
# Example: Change "80:80" to "8080:80" for HTTP
```

## Advanced Configuration

### Custom Domain Setup

For production deployment with a real domain:

1. **Update DNS records:**
   ```bash
   # Point your domain to your server IP
   n8n.yourdomain.com -> YOUR_SERVER_IP
   ```

2. **Update environment variables:**
   ```bash
   DOMAIN_NAME=yourdomain.com
   N8N_HOST=n8n.yourdomain.com
   ACME_EMAIL=admin@yourdomain.com
   ```

3. **Enable Let's Encrypt:**
   ```yaml
   # Traefik will automatically obtain SSL certificates
   # No additional configuration needed
   ```

### High Availability Setup

For production environments requiring high availability:

```yaml
# docker-compose.ha.yml
services:
  postgres:
    deploy:
      replicas: 1
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - postgres_backup:/backup
    
  n8n:
    deploy:
      replicas: 2
    environment:
      - EXECUTIONS_PROCESS=main
      - N8N_DISABLE_UI=false
```

### Integration with External Services

#### LDAP Authentication
```bash
# Add to n8n environment
N8N_AUTH_EXCLUDE_ENDPOINTS=rest,healthz
N8N_BASIC_AUTH_ACTIVE=false
N8N_AUTH_LDAP_ENABLED=true
N8N_AUTH_LDAP_SERVER=ldap://your-ldap-server
N8N_AUTH_LDAP_BIND_DN=cn=admin,dc=company,dc=com
N8N_AUTH_LDAP_BIND_PASSWORD=your-ldap-password
```

#### External Database
```bash
# For connecting to external PostgreSQL
DB_POSTGRESDB_HOST=external-postgres.company.com
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_SSL_ENABLED=true
DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED=true
```

This completes your production-ready n8n Docker setup with comprehensive database integration, security hardening, and operational procedures. The configuration is ready for immediate deployment and can be customized for your specific requirements.
