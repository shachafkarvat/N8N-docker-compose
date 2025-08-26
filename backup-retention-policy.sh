#!/bin/bash

# Advanced Backup Retention Policy
# Author: Backup retention system for Docker Compose n8n deployment
# Date: August 2025
# Description: Implements tiered backup retention with daily, weekly, and monthly archives
#
# Retention Strategy:
# - Last 7 days: Keep ALL daily backups (granular recovery)
# - Weekly: Keep last 4 Sunday backups (medium-term recovery)
# - Monthly: Keep ALL 1st-of-month backups (permanent long-term archive)
#
# Usage: 
#   BACKUP_DIR="./backups" ./backup-retention-policy.sh
#   Or source this script from your main backup script

# Configuration
BACKUP_DIR="${BACKUP_DIR:-./backups}"

echo "=== Advanced Backup Retention Policy ==="
echo "Retention Strategy:"
echo "   - Daily: Keep all backups from last 7 days"
echo "   - Weekly: Keep last 4 Sunday backups"
echo "   - Monthly: Keep all 1st-of-month backups (permanent)"
echo

# Get current date info
current_date=$(date +%Y%m%d)
seven_days_ago=$(date -d "7 days ago" +%Y%m%d)

echo "Analysis Date: $(date)"
echo "Cutoff Date: $(date -d "7 days ago")"
echo

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
echo "Calculating protected Sunday dates..."
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
echo

# Process each backup folder (expects YYYYMMDD_HHMMSS format)
deleted_count=0
kept_count=0

for backup_folder in "$BACKUP_DIR"/202*; do
    if [ -d "$backup_folder" ]; then
        folder_name=$(basename "$backup_folder")
        backup_date=${folder_name:0:8}  # Extract YYYYMMDD from folder name
        
        # Skip if backup is from last 7 days
        if [ "$backup_date" -ge "$seven_days_ago" ]; then
            echo "KEEP: $folder_name (within 7 days)"
            ((kept_count++))
            continue
        fi
        
        # Check if it's a 1st of month backup
        if is_first_of_month "$backup_date"; then
            echo "KEEP: $folder_name (1st of month - permanent archive)"
            ((kept_count++))
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
            echo "KEEP: $folder_name (Sunday weekly backup)"
            ((kept_count++))
            continue
        fi
        
        # If we reach here, delete the backup
        echo "DELETE: $folder_name (outside retention policy)"
        rm -rf "$backup_folder"
        ((deleted_count++))
    fi
done

echo
echo "Retention Summary:"
echo "   - Backups kept: $kept_count"
echo "   - Backups deleted: $deleted_count"
echo "   - Policy applied successfully"

# Example integration with backup script:
#
# #!/bin/bash
# # main-backup.sh
# 
# # Create timestamped backup folder
# DATE=$(date +%Y%m%d_%H%M%S)
# BACKUP_FOLDER="./backups/$DATE"
# mkdir -p "$BACKUP_FOLDER"
# 
# # Create your backups
# echo "Creating database backup..."
# docker compose exec -T postgres pg_dump -U postgres mydb > "$BACKUP_FOLDER/database.sql"
# 
# echo "Creating data volume backup..."
# docker run --rm -v myapp_data:/data:ro -v "$BACKUP_FOLDER":/backup alpine tar czf /backup/data.tar.gz -C /data .
# 
# echo "Creating configuration backup..."
# cp docker-compose.yml "$BACKUP_FOLDER/"
# cp .env "$BACKUP_FOLDER/env.txt"
# 
# # Apply retention policy
# export BACKUP_DIR="./backups"
# ./backup-retention-policy.sh