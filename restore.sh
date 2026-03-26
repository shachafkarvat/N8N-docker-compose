#!/bin/bash

# N8N Restore Script
# Restores n8n data and PostgreSQL database from a timestamped backup folder

set -e

# Check if backup folder name is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_folder>"
    echo "Example: $0 20240202_143000"
    echo ""
    echo "Available backups:"
    if ls -d ./backups/202* > /dev/null 2>&1; then
        ls -1d ./backups/202* | xargs -I{} basename {}
    else
        echo "No backups found in ./backups/"
    fi
    exit 1
fi

BACKUP_DATE="$1"
BACKUP_DIR="./backups"
BACKUP_FOLDER="$BACKUP_DIR/$BACKUP_DATE"

# Validate backup folder exists with required files
if [ ! -d "$BACKUP_FOLDER" ]; then
    echo "Error: Backup folder not found: $BACKUP_FOLDER"
    echo ""
    echo "Available backups:"
    ls -1d ./backups/202* 2>/dev/null | xargs -I{} basename {} || echo "None"
    exit 1
fi

if [ ! -f "$BACKUP_FOLDER/postgres.sql" ]; then
    echo "Error: PostgreSQL dump not found: $BACKUP_FOLDER/postgres.sql"
    exit 1
fi

if [ ! -f "$BACKUP_FOLDER/n8n_data.tar.gz" ]; then
    echo "Error: N8N data backup not found: $BACKUP_FOLDER/n8n_data.tar.gz"
    exit 1
fi

echo "Restoring from backup: $BACKUP_DATE"
if [ -f "$BACKUP_FOLDER/backup_info.txt" ]; then
    echo ""
    echo "--- Backup info ---"
    cat "$BACKUP_FOLDER/backup_info.txt"
    echo "-------------------"
fi
echo ""

# Confirm with user
read -p "This will OVERWRITE existing data. Are you sure? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Restore cancelled."
    exit 1
fi

echo "Starting restore process..."

# Stop services
echo "Stopping services..."
docker compose down

# Start only PostgreSQL for database restore
echo "Starting PostgreSQL for database restore..."
docker compose up -d postgres

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
sleep 5
while ! docker compose exec postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" > /dev/null 2>&1; do
    echo "Waiting for PostgreSQL..."
    sleep 3
done
echo "PostgreSQL is ready."

# Drop and recreate database for a clean restore
echo "Recreating database..."
docker compose exec postgres psql -U "${POSTGRES_USER:-n8n}" -d postgres -c "DROP DATABASE IF EXISTS \"${POSTGRES_DB:-n8n}\";"
docker compose exec postgres psql -U "${POSTGRES_USER:-n8n}" -d postgres -c "CREATE DATABASE \"${POSTGRES_DB:-n8n}\";"

# Restore PostgreSQL database
echo "Restoring PostgreSQL database..."
docker compose exec -T postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" < "$BACKUP_FOLDER/postgres.sql"

# Stop PostgreSQL
docker compose stop postgres

# Restore n8n data volume
echo "Restoring n8n data volume..."
docker run --rm \
    -v compose_n8n_data:/data \
    -v "$(pwd)/$BACKUP_FOLDER":/backup \
    alpine:latest \
    sh -c "rm -rf /data/* /data/.[^.]* && tar xzf /backup/n8n_data.tar.gz -C /data"

# Restore local-files if backup exists
if [ -f "$BACKUP_FOLDER/local_files.tar.gz" ]; then
    echo "Restoring local-files directory..."
    rm -rf ./local-files
    tar xzf "$BACKUP_FOLDER/local_files.tar.gz"
fi

# Offer config restore if available
if [ -f "$BACKUP_FOLDER/docker-compose.yml" ] && [ ! -f "./docker-compose.yml.backup" ]; then
    echo "Backup docker-compose.yml available at: $BACKUP_FOLDER/docker-compose.yml"
    echo "Current docker-compose.yml left untouched (backup copy preserved)."
fi

# Start all services
echo "Starting all services..."
docker compose up -d

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 15

# Check service status
echo "Service status:"
docker compose ps

echo ""
echo "Restore completed successfully!"
echo "Restored from backup: $BACKUP_DATE"
echo ""
echo "Please verify your n8n instance is working correctly at:"
echo "https://${SUBDOMAIN:-n8n}.${DOMAIN_NAME:-localhost}"
echo ""
echo "If you encounter issues, check the logs:"
echo "  docker compose logs n8n"
echo "  docker compose logs postgres"
