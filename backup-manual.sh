#!/bin/bash

# Manual Backup Script
# Run this script manually to create an immediate backup

# Load environment variables from .env if present
if [ -f "$(dirname "$0")/.env" ]; then
    set -a
    source "$(dirname "$0")/.env"
    set +a
fi

# Create backups directory
mkdir -p ./backups

# Set environment variables for the backup script
export BACKUP_DIR="$(pwd)/backups"

# Run the backup
./backup.sh

echo ""
echo "Manual backup completed!"
echo "To enable daily automatic backups, run:"
echo "docker compose --profile backup up -d backup"
echo ""
echo "To disable automatic backups, run:"
echo "docker compose stop backup && docker compose rm -f backup"