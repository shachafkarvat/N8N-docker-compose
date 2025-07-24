#!/bin/bash
# scripts/health-check.sh

set -euo pipefail

echo "🏥 Running health checks..."

# Check Docker services
if ! docker compose ps | grep -q "Up"; then
    echo "❌ Some services are not running"
    docker compose ps
    exit 1
fi

# Check n8n accessibility
if ! curl -k -s -f https://localhost > /dev/null; then
    echo "❌ n8n is not accessible"
    exit 1
fi

# Check database connectivity
if ! docker exec n8n-postgres pg_isready -U postgres -d n8n > /dev/null; then
    echo "❌ PostgreSQL is not ready"
    exit 1
fi

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 80 ]]; then
    echo "⚠️ Disk usage is ${DISK_USAGE}% (>80%)"
fi

# Check memory usage
MEMORY_USAGE=$(free | grep '^Mem:' | awk '{printf "%.0f", $3/$2*100}')
if [[ $MEMORY_USAGE -gt 90 ]]; then
    echo "⚠️ Memory usage is ${MEMORY_USAGE}% (>90%)"
fi

echo "✅ All health checks passed"
