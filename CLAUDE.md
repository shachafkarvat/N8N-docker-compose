# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

This is a production-ready n8n workflow automation platform deployed via Docker Compose with:

- **n8n**: Workflow automation engine (stable version, 24G memory limit, 4G reservation)
- **Traefik**: Reverse proxy with SSL termination and automatic HTTPS via Let's Encrypt
- **PostgreSQL 16**: Database backend for n8n data storage
- **Backup Service**: Alpine-based cron service for automated daily backups at 2 AM

The full stack is deployed via docker-compose.yml with all services active.

## Key Configuration Files

- `docker-compose.yml`: Main service definitions (n8n, Traefik, PostgreSQL, Backup)
- `.env`: Environment variables (contains sensitive data - never commit)
- `config/traefik.yml`: Traefik static configuration
- `config/dynamic/`: Traefik dynamic configuration and TLS settings
- `scripts/`: Operational scripts for deployment and maintenance
- `local-files/`: Mounted volume for file access within n8n workflows
- `backups/`: Backup storage directory with timestamped folders
- `backup.sh` / `restore.sh`: Backup and restore scripts

## Common Commands

### Setup and Deployment
```bash
# Install Docker and dependencies
./scripts/install-dependencies.sh

# Deploy the stack
./scripts/deploy.sh

# Verify setup
./scripts/verify-setup.sh
```

### Daily Operations
```bash
# View service status
docker compose ps

# View logs
docker compose logs -f n8n        # n8n application
docker compose logs -f traefik    # proxy/SSL

# Restart services
docker compose restart n8n
docker compose restart traefik

# Stop/start all services
docker compose down
docker compose up -d

# Update to latest images
docker compose pull
docker compose up -d
```

### Backup and Maintenance
```bash
# Create backup (manual)
./backup.sh

# Restore from backup
./restore.sh

# Health check
./scripts/health-check.sh

# Access n8n container
docker exec -it n8n /bin/sh

# Access PostgreSQL
docker exec -it compose-postgres-1 psql -U n8n -d n8n
```

### Debugging
```bash
# Check connectivity
curl -k https://n8n.localhost
curl -k https://localhost

# Check Traefik dashboard
curl http://localhost:8081

# Test SSL certificates
openssl s_client -connect localhost:8443 -servername n8n.localhost
```

## Environment Configuration

The `.env` file contains critical configuration:

- **Domain Settings**: `DOMAIN_NAME`, `SUBDOMAIN` (combined as `${SUBDOMAIN}.${DOMAIN_NAME}`)
- **SSL**: `SSL_EMAIL` for Let's Encrypt certificates
- **Database**: `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (defaults to `n8n` if not set)
- **Timezone**: `GENERIC_TIMEZONE`
- **n8n Settings**: `N8N_RUNNERS_ENABLED` (defaults to true)

## Port Mapping

- `8080`: HTTP (redirects to HTTPS)
- `8443`: HTTPS for n8n access
- `8081`: Traefik dashboard
- `5678`: n8n direct access (localhost only)

## SSL/TLS Configuration

- Self-signed certificates generated automatically for localhost
- Let's Encrypt integration available for production domains
- Traefik handles certificate management and renewal
- Custom certificates can be placed in `config/dynamic/`

## Volume Mounts

- `n8n_data`: Persistent n8n workflow and configuration data
- `postgres_data`: PostgreSQL database files
- `traefik_data`: SSL certificates (Let's Encrypt acme.json)
- `./local-files:/files`: Host directory mounted for file operations in n8n
- `./backups:/backups`: Backup storage directory

## Security Considerations

- Basic authentication enabled by default
- Non-root container execution
- Read-only Docker socket access for Traefik
- SSL/TLS encryption for all external traffic
- Environment-based secret management

## Troubleshooting Commands

When issues occur, always check:

1. **Service Status**: `docker compose ps`
2. **Logs**: `docker compose logs [service_name]`
3. **Connectivity**: `curl -k https://localhost` or `https://n8n.localhost`
4. **Port Conflicts**: `sudo netstat -tulpn | grep :8080`
5. **Certificate Issues**: Check `config/dynamic/` directory

## Development Workflow

When modifying the setup:

1. Test changes in development environment first
2. Backup existing configuration: `./scripts/backup.sh`
3. Apply changes to docker-compose.yml or scripts
4. Redeploy: `docker compose down && docker compose up -d`
5. Verify functionality: `./scripts/health-check.sh`

## Host Configuration

For local development, add to `/etc/hosts`:
```
127.0.0.1 n8n.localhost traefik.localhost
```

For production deployment, ensure DNS points to server IP:
- n8n.yourdomain.com → server_ip
- traefik.yourdomain.com → server_ip (optional)