#!/bin/bash

# N8N Restore Script
# Restores n8n data and PostgreSQL database from backup

set -e

# Check if backup date is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <backup_date>"
    echo "Example: $0 20240202_143000"
    echo ""
    echo "Available backups:"
    ls -la ./backups/backup_info_*.txt | sed 's/.*backup_info_\(.*\)\.txt/\1/' || echo "No backups found"
    exit 1
fi

BACKUP_DATE="$1"
BACKUP_DIR="./backups"

# Check if backup files exist
if [ ! -f "$BACKUP_DIR/postgres_${BACKUP_DATE}.sql" ]; then
    echo "Error: PostgreSQL backup file not found: $BACKUP_DIR/postgres_${BACKUP_DATE}.sql"
    exit 1
fi

if [ ! -f "$BACKUP_DIR/n8n_data_${BACKUP_DATE}.tar.gz" ]; then
    echo "Error: N8N data backup file not found: $BACKUP_DIR/n8n_data_${BACKUP_DATE}.tar.gz"
    exit 1
fi

echo "Restoring from backup: $BACKUP_DATE"
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
sleep 10
while ! docker compose exec postgres pg_isready -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" > /dev/null 2>&1; do
    echo "Waiting for PostgreSQL..."
    sleep 5
done

# Drop and recreate database to ensure clean restore
echo "Recreating database..."
docker compose exec postgres psql -U "${POSTGRES_USER:-n8n}" -d postgres -c "DROP DATABASE IF EXISTS \"${POSTGRES_DB:-n8n}\";"
docker compose exec postgres psql -U "${POSTGRES_USER:-n8n}" -d postgres -c "CREATE DATABASE \"${POSTGRES_DB:-n8n}\";"

# Restore PostgreSQL database
echo "Restoring PostgreSQL database..."
docker compose exec -T postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" < "$BACKUP_DIR/postgres_${BACKUP_DATE}.sql"

# Stop PostgreSQL
docker compose stop postgres

# Restore n8n data volume
echo "Restoring n8n data volume..."
docker run --rm \
  -v compose_n8n_data:/data \
  -v "$(pwd)/$BACKUP_DIR":/backup \
  alpine:latest \
  sh -c "rm -rf /data/* /data/.[^.]* && tar xzf /backup/n8n_data_${BACKUP_DATE}.tar.gz -C /data"

# Restore local-files if backup exists
if [ -f "$BACKUP_DIR/local_files_${BACKUP_DATE}.tar.gz" ]; then
    echo "Restoring local-files directory..."
    rm -rf ./local-files
    tar xzf "$BACKUP_DIR/local_files_${BACKUP_DATE}.tar.gz"
fi

# Restore configuration files if needed
if [ -f "$BACKUP_DIR/docker-compose_${BACKUP_DATE}.yml" ] && [ ! -f "./docker-compose.yml.backup" ]; then
    echo "Backing up current docker-compose.yml and offering to restore from backup..."
    cp docker-compose.yml docker-compose.yml.backup
    echo "Current docker-compose.yml backed up as docker-compose.yml.backup"
    echo "Backup docker-compose.yml available at: $BACKUP_DIR/docker-compose_${BACKUP_DATE}.yml"
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
echo "Please verify that your n8n instance is working correctly at:"
echo "https://${SUBDOMAIN:-n8n}.${DOMAIN_NAME:-localhost}"
echo ""
echo "If you encounter issues, check the logs:"
echo "docker compose logs n8n"
echo "docker compose logs postgres"