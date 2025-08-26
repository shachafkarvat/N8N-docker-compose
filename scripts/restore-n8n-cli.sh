#!/bin/bash
# Restore n8n workflows and credentials using n8n CLI

set -euo pipefail

# Path to backup files
WORKFLOWS_JSON="${1:-./local-files/backups/latest/file.json}"
CREDS_JSON="${2:-./local-files/backups/latest/creds.json}"

# Container name for n8n
N8N_CONTAINER="compose-n8n-1"

if [ ! -f "$WORKFLOWS_JSON" ]; then
  echo "Workflows file not found: $WORKFLOWS_JSON"
  exit 1
fi
if [ ! -f "$CREDS_JSON" ]; then
  echo "Credentials file not found: $CREDS_JSON"
  exit 1
fi

echo "Restoring workflows from $WORKFLOWS_JSON..."
docker cp "$WORKFLOWS_JSON" "$N8N_CONTAINER:/tmp/workflows.json"
docker exec "$N8N_CONTAINER" n8n import:workflow --input=/tmp/workflows.json

echo "Restoring credentials from $CREDS_JSON..."
docker cp "$CREDS_JSON" "$N8N_CONTAINER:/tmp/creds.json"
docker exec "$N8N_CONTAINER" n8n import:credentials --input=/tmp/creds.json

echo "Restore completed using n8n CLI."
