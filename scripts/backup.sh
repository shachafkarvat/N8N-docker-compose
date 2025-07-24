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
