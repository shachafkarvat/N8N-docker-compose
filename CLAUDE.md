# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture Overview

Production n8n workflow automation platform deployed via Docker Compose:

- **n8n**: Custom-built from `n8n.Dockerfile` (base: `n8nio/n8n:stable` + cheerio npm package). 24G memory limit, 4G reservation. Runs as `node` user.
- **Traefik**: Reverse proxy with automatic HTTPS (Let's Encrypt TLS challenge) and HTTP-to-HTTPS redirect.
- **PostgreSQL 16**: Database backend with healthcheck. n8n waits for healthy postgres before starting.
- **Backup Service**: Alpine container running cron (`restart: "no"` — only runs while stack is up). Daily backups at 2 AM with tiered retention (7 days all, 4 weekly Sundays, monthly 1st-of-month forever).

## Custom n8n Image

n8n uses a custom Dockerfile (`n8n.Dockerfile`) rather than the stock image. The `NODE_FUNCTION_ALLOW_EXTERNAL=cheerio` env var in docker-compose.yml allows n8n Code nodes to `require('cheerio')`. When adding new npm packages for use in Code nodes, update both the Dockerfile and the environment variable.

To rebuild after Dockerfile changes:
```bash
docker compose build n8n
docker compose up -d n8n
```

## Common Commands

```bash
# Initial setup
cp .env.example .env  # then edit with real values
./scripts/deploy.sh   # builds, pulls, starts, verifies

# Daily operations
docker compose ps
docker compose logs -f n8n
docker compose logs -f traefik
docker compose restart n8n
docker compose down && docker compose up -d

# Manual backup
./backup.sh

# Restore (requires backup folder name, e.g. 20240202_143000)
./restore.sh <backup_date>

# Database access
docker exec -it compose-postgres-1 psql -U n8n -d n8n

# n8n container shell
docker exec -it n8n /bin/sh

# Debugging
curl -k https://n8n.localhost        # test via Traefik
curl http://localhost:5678           # test n8n directly (localhost only)
curl http://localhost:8081           # Traefik dashboard/API
```

## Port Mapping

| Host Port | Container Port | Service | Notes |
|-----------|---------------|---------|-------|
| 8080 | 80 | Traefik | HTTP, redirects to HTTPS |
| 8443 | 443 | Traefik | HTTPS for n8n access |
| 8081 | 8080 | Traefik | Dashboard/API (insecure mode) |
| 5678 | 5678 | n8n | Direct access, localhost-only bind |

## Environment Configuration

The `.env` file drives all service configuration. Key variables (see `.env.example` for template):

- `DOMAIN_NAME` / `SUBDOMAIN`: Combined as `${SUBDOMAIN}.${DOMAIN_NAME}` for Traefik routing and n8n host config
- `SSL_EMAIL` / `ACME_EMAIL`: For Let's Encrypt certificate registration
- `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`: Database credentials (defaults to `n8n` in docker-compose.yml)
- `GENERIC_TIMEZONE`: Timezone for n8n
- `N8N_RUNNERS_ENABLED`: Task runners (defaults to `true`)

## Known Issues / Gotchas

- **Backup/restore mismatch**: `backup.sh` saves files into timestamped folders (`backups/YYYYMMDD_HHMMSS/postgres.sql`), but `restore.sh` expects flat files with date suffixes (`backups/postgres_YYYYMMDD_HHMMSS.sql`). The restore script needs updating to match the backup format, or use the manual restore steps from `backup_info.txt`.
- **Backup service restart policy**: Set to `restart: "no"`, so it won't restart if it crashes. Check `docker compose ps` to verify it's running.
- **n8n log level**: Set to `debug` in production — consider changing to `warn` or `error` for less noise.
- **NODE_OPTIONS**: `--max-old-space-size=3072` (3GB) is set for n8n's Node.js process.

## Volume Mounts

- `n8n_data` → `/home/node/.n8n`: Persistent n8n data
- `postgres_data` → `/var/lib/postgresql/data`: Database files
- `traefik_data` → `/letsencrypt`: SSL certificates (acme.json)
- `./local-files` → `/files`: Host directory for n8n workflow file operations
- `./backups` → `/backups`: Backup storage

## SSL/TLS

- `scripts/deploy.sh` auto-generates self-signed certs for localhost development
- Production uses Let's Encrypt via Traefik's TLS challenge resolver
- Traefik dynamic TLS config in `config/dynamic/tls.yml`

## Host Configuration (Local Dev)

Add to `/etc/hosts`:
```
127.0.0.1 n8n.localhost traefik.localhost
```