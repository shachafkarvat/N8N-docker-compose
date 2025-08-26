#!/bin/bash

# N8N Daily Backup Script
# Backs up both n8n data volume and PostgreSQL database

set -e

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATE=$(date +%Y%m%d_%H%M%S)
COMPOSE_PROJECT_NAME="compose"
RETENTION_DAYS=30

# Create backup directory structure: backups/YYYYMMDD_HHMMSS/
BACKUP_FOLDER="$BACKUP_DIR/$DATE"
mkdir -p "$BACKUP_FOLDER"

echo "Starting backup at $(date)"

# Backup PostgreSQL database
echo "Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump -U "${POSTGRES_USER:-postgres}" "${POSTGRES_DB:-n8n}" > "$BACKUP_FOLDER/postgres.sql"

# Backup n8n data volume
echo "Backing up n8n data volume..."
docker run --rm \
  -v ${COMPOSE_PROJECT_NAME}_n8n_data:/data:ro \
  -v "$BACKUP_FOLDER":/backup \
  alpine:latest \
  tar czf "/backup/n8n_data.tar.gz" -C /data .

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
1. Stop services: docker compose down
2. Restore database: docker compose exec -T postgres psql -U postgres -d n8n < $DATE/postgres.sql
3. Restore n8n data: docker run --rm -v compose_n8n_data:/data -v $(pwd)/backups/$DATE:/backup alpine tar xzf /backup/n8n_data.tar.gz -C /data
4. Start services: docker compose up -d
EOF

# Advanced backup retention cleanup
echo "Applying backup retention policy..."
echo "- Keeping all backups from last 7 days"
echo "- Keeping last 4 Sunday backups"
echo "- Keeping all 1st-of-month backups"

# Temporarily disable verbose output for retention logic
set +x

# Get current date info
current_date=$(date +%Y%m%d)
seven_days_ago=$(date -d "7 days ago" +%Y%m%d)

# Function to check if a date is a Sunday
is_sunday() {
    local date_str="$1"
    local year=${date_str:0:4}
    local month=${date_str:4:2}
    local day=${date_str:6:2}
    local day_of_week=$(date -d "${year}-${month}-${day}" +%u)
    [ "$day_of_week" -eq 7 ]
}

# Function to check if a date is the 1st of the month
is_first_of_month() {
    local date_str="$1"
    local day=${date_str:6:2}
    [ "$day" = "01" ]
}

# Get list of Sunday backup dates (last 4 Sundays)
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
        backup_date=${folder_name:0:8}  # Extract YYYYMMDD from folder name
        
        # Skip if backup is from last 7 days
        if [ "$backup_date" -ge "$seven_days_ago" ]; then
            echo "Keeping recent backup: $folder_name (within 7 days)"
            continue
        fi
        
        # Check if it's a 1st of month backup
        if is_first_of_month "$backup_date"; then
            echo "Keeping monthly backup: $folder_name (1st of month)"
            continue
        fi
        
        # Check if it's one of the last 4 Sunday backups
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
        
        # If we reach here, delete the backup
        echo "Deleting backup: $folder_name (outside retention policy)"
        rm -rf "$backup_folder"
    fi
done

# Re-enable verbose output
set -x

echo "Backup completed successfully at $(date)"
echo "Backup folder: $BACKUP_FOLDER"
echo "Backup files:"
ls -la "$BACKUP_FOLDER"

# Calculate backup sizes
echo "Backup sizes:"
du -h "$BACKUP_FOLDER"/*