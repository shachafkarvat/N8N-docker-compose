#!/bin/bash
# scripts/backup.sh

set -euo pipefail

BACKUP_DIR="./backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

echo "🗄️ Creating backup for $DATE..."

# Backup database (full SQL dump, not just gzip)
echo "📊 Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-n8n}" "${POSTGRES_DB:-n8n}" > "$BACKUP_DIR/postgres_${DATE}.sql"

# Backup n8n data volume
echo "⚙️ Backing up n8n data..."
docker run --rm -v compose_n8n_data:/data -v "$PWD/$BACKUP_DIR":/backup alpine tar czf /backup/n8n_data_${DATE}.tar.gz -C /data .

# Backup configuration
echo "📝 Backing up configuration..."
tar czf "$BACKUP_DIR/config_${DATE}.tar.gz" docker-compose.yml .env config/

# Cleanup old backups (keep last 7 days)
find "$BACKUP_DIR" -name "*.gz" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete

echo "✅ Backup completed: $BACKUP_DIR"
echo "📦 Files created:"
ls -lh "$BACKUP_DIR"/*${DATE}*
