#!/bin/bash

# N8N Daily Backup Script
# Backs up both n8n data volume and PostgreSQL database

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
COMPOSE_PROJECT_NAME="compose"

# Create backup directory structure: backups/YYYYMMDD_HHMMSS/
BACKUP_FOLDER="$BACKUP_DIR/$DATE"
mkdir -p "$BACKUP_FOLDER"

echo "Starting backup at $(date)"

# Auto-detect: container mode = running inside the backup container
# (n8n_data is mounted at /n8n_data AND we are not the Docker host)
# Host mode = running directly on the Docker host
if [ -d "/n8n_data" ] && [ -f "/.dockerenv" ]; then
    CONTAINER_MODE=true
    echo "Mode: container (using direct pg_dump and mounted volume)"
else
    CONTAINER_MODE=false
    echo "Mode: host (using docker compose exec and docker run)"
fi

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
if [ "$CONTAINER_MODE" = "true" ]; then
    PGPASSWORD="${POSTGRES_PASSWORD}" pg_dump \
        -h postgres \
        -U "${POSTGRES_USER:-n8n}" \
        "${POSTGRES_DB:-n8n}" > "$BACKUP_FOLDER/postgres.sql"
else
    docker compose exec -T postgres pg_dump \
        -U "${POSTGRES_USER:-n8n}" \
        "${POSTGRES_DB:-n8n}" > "$BACKUP_FOLDER/postgres.sql"
fi

# Backup n8n data volume
echo "Backing up n8n data volume..."
if [ "$CONTAINER_MODE" = "true" ]; then
    tar czf "$BACKUP_FOLDER/n8n_data.tar.gz" -C /n8n_data .
else
    docker run --rm \
        -v ${COMPOSE_PROJECT_NAME}_n8n_data:/data:ro \
        -v "$BACKUP_FOLDER":/backup \
        alpine:latest \
        tar czf "/backup/n8n_data.tar.gz" -C /data .
fi

# Backup local-files directory
if [ -d "./local-files" ]; then
    echo "Backing up local-files directory..."
    tar czf "$BACKUP_FOLDER/local_files.tar.gz" -C . local-files
fi

# Backup docker-compose.yml and .env
echo "Backing up configuration files..."
cp docker-compose.yml "$BACKUP_FOLDER/docker-compose.yml"
if [ -f ".env" ]; then
    cp .env "$BACKUP_FOLDER/env.txt"
fi

# Create a combined backup info file
cat > "$BACKUP_FOLDER/backup_info.txt" << EOF
Backup created: $(date)
Backup folder: $DATE
PostgreSQL dump: postgres.sql
N8N data volume: n8n_data.tar.gz
Local files: local_files.tar.gz
Docker compose: docker-compose.yml
Environment: env.txt

To restore:
  ./restore.sh $DATE
EOF

# Advanced backup retention cleanup
echo "Applying backup retention policy..."
echo "- Keeping all backups from last 7 days"
echo "- Keeping last 4 Sunday backups"
echo "- Keeping all 1st-of-month backups"

set +e

# Get current date info
seven_days_ago=$(date -d "7 days ago" +%Y%m%d)

# Check if a date string (YYYYMMDD) falls on a Sunday
is_sunday() {
    local date_str="$1"
    local year=${date_str:0:4}
    local month=${date_str:4:2}
    local day=${date_str:6:2}
    local day_of_week
    day_of_week=$(date -d "${year}-${month}-${day}" +%u)
    [ "$day_of_week" -eq 7 ]
}

# Check if a date string (YYYYMMDD) is the 1st of the month
is_first_of_month() {
    local date_str="$1"
    local day=${date_str:6:2}
    [ "$day" = "01" ]
}

# Collect the last 4 Sunday dates
sunday_backups=()
temp_date=$(date +%Y%m%d)
sunday_count=0
while [ $sunday_count -lt 4 ]; do
    if is_sunday "$temp_date"; then
        sunday_backups+=("$temp_date")
        ((sunday_count++))
    fi
    temp_date=$(date -d "$temp_date -1 day" +%Y%m%d)
done

echo "Protected Sunday dates: ${sunday_backups[*]}"

# Process each backup folder
for backup_folder in "$BACKUP_DIR"/202*; do
    if [ -d "$backup_folder" ]; then
        folder_name=$(basename "$backup_folder")
        backup_date=${folder_name:0:8}  # Extract YYYYMMDD

        if [ "$backup_date" -ge "$seven_days_ago" ]; then
            echo "Keeping recent backup: $folder_name (within 7 days)"
            continue
        fi

        if is_first_of_month "$backup_date"; then
            echo "Keeping monthly backup: $folder_name (1st of month)"
            continue
        fi

        keep_sunday=false
        for sunday_date in "${sunday_backups[@]}"; do
            if [ "$backup_date" = "$sunday_date" ]; then
                keep_sunday=true
                break
            fi
        done

        if [ "$keep_sunday" = true ]; then
            echo "Keeping weekly backup: $folder_name (Sunday backup)"
            continue
        fi

        echo "Deleting backup: $folder_name (outside retention policy)"
        rm -rf "$backup_folder"
    fi
done

set -e

echo "Backup completed successfully at $(date)"
echo "Backup folder: $BACKUP_FOLDER"
echo "Backup files:"
ls -la "$BACKUP_FOLDER"
echo "Backup sizes:"
du -h "$BACKUP_FOLDER"/*
