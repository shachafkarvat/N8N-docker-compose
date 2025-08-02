#!/bin/bash

# N8N Daily Backup Script
# Backs up both n8n data volume and PostgreSQL database

set -e

# Configuration
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
COMPOSE_PROJECT_NAME="compose"
RETENTION_DAYS=30

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "Starting backup at $(date)"

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_DIR/postgres_${DATE}.sql"

# Backup n8n data volume
echo "Backing up n8n data volume..."
docker run --rm \
  -v ${COMPOSE_PROJECT_NAME}_n8n_data:/data:ro \
  -v "$BACKUP_DIR":/backup \
  alpine:latest \
  tar czf "/backup/n8n_data_${DATE}.tar.gz" -C /data .

# Backup local-files directory
if [ -d "./local-files" ]; then
  echo "Backing up local-files directory..."
  tar czf "$BACKUP_DIR/local_files_${DATE}.tar.gz" -C . local-files
fi

# Backup docker-compose.yml and .env
echo "Backing up configuration files..."
cp docker-compose.yml "$BACKUP_DIR/docker-compose_${DATE}.yml"
if [ -f ".env" ]; then
  cp .env "$BACKUP_DIR/env_${DATE}.txt"
fi

# Create a combined backup info file
cat > "$BACKUP_DIR/backup_info_${DATE}.txt" << EOF
Backup created: $(date)
PostgreSQL dump: postgres_${DATE}.sql
N8N data volume: n8n_data_${DATE}.tar.gz
Local files: local_files_${DATE}.tar.gz
Docker compose: docker-compose_${DATE}.yml
Environment: env_${DATE}.txt

To restore:
1. Stop services: docker compose down
2. Restore database: docker compose exec -T postgres psql -U n8n -d n8n < postgres_${DATE}.sql
3. Restore n8n data: docker run --rm -v compose_n8n_data:/data -v $(pwd)/backups:/backup alpine tar xzf /backup/n8n_data_${DATE}.tar.gz -C /data
4. Start services: docker compose up -d
EOF

# Cleanup old backups
echo "Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "postgres_*.sql" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "n8n_data_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "local_files_*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "docker-compose_*.yml" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "env_*.txt" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "backup_info_*.txt" -mtime +$RETENTION_DAYS -delete

echo "Backup completed successfully at $(date)"
echo "Backup files:"
ls -la "$BACKUP_DIR"/*_${DATE}*

# Calculate backup sizes
echo "Backup sizes:"
du -h "$BACKUP_DIR"/*_${DATE}*