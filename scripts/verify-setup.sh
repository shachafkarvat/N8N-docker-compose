#!/bin/bash
# scripts/verify-setup.sh
# Comprehensive verification script for n8n Docker setup

set -euo pipefail

echo "🔍 Verifying n8n Docker Setup..."
echo "================================="

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    echo "❌ Please run this script from the n8n compose directory"
    exit 1
fi

# Check required files
echo "📋 Checking required files..."
REQUIRED_FILES=(
    "docker-compose.yml"
    ".env"
    "init.sql"
    "config/traefik.yml"
    "scripts/deploy.sh"
    "scripts/backup.sh"
    "scripts/health-check.sh"
    "scripts/install-dependencies.sh"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "  ✅ $file"
    else
        echo "  ❌ $file (missing)"
        exit 1
    fi
done

# Check Docker installation
echo ""
echo "🐳 Checking Docker installation..."
if command -v docker &> /dev/null; then
    echo "  ✅ Docker installed: $(docker --version)"
else
    echo "  ❌ Docker not installed. Run: ./scripts/install-dependencies.sh"
    exit 1
fi

if command -v docker compose &> /dev/null || docker compose version &> /dev/null; then
    echo "  ✅ Docker Compose available"
else
    echo "  ❌ Docker Compose not available"
    exit 1
fi

# Check NVIDIA setup (optional)
echo ""
echo "🖥️ Checking NVIDIA setup..."
if command -v nvidia-smi &> /dev/null; then
    echo "  ✅ NVIDIA driver installed"
    if command -v nvidia-container-toolkit &> /dev/null || docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi &> /dev/null; then
        echo "  ✅ NVIDIA Container Toolkit available"
    else
        echo "  ⚠️ NVIDIA Container Toolkit not available (GPU features disabled)"
    fi
else
    echo "  ⚠️ NVIDIA driver not found (GPU features disabled)"
fi

# Check environment variables
echo ""
echo "🔧 Checking environment configuration..."
source .env
REQUIRED_VARS=(
    "DOMAIN_NAME"
    "N8N_HOST"
    "POSTGRES_DB"
    "POSTGRES_USER"
    "POSTGRES_PASSWORD"
    "POSTGRES_NON_ROOT_USER"
    "POSTGRES_NON_ROOT_PASSWORD"
    "N8N_BASIC_AUTH_USER"
    "N8N_BASIC_AUTH_PASSWORD"
)

for var in "${REQUIRED_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        echo "  ✅ $var is set"
    else
        echo "  ❌ $var is not set"
        exit 1
    fi
done

# Check for weak passwords
echo ""
echo "🔐 Checking password security..."
PASSWORDS=(
    "$POSTGRES_PASSWORD"
    "$POSTGRES_NON_ROOT_PASSWORD"
    "$N8N_BASIC_AUTH_PASSWORD"
)

for password in "${PASSWORDS[@]}"; do
    if [[ ${#password} -lt 12 ]]; then
        echo "  ⚠️ Password is less than 12 characters (weak)"
    elif [[ ${#password} -ge 16 ]]; then
        echo "  ✅ Password length is good (16+ characters)"
    else
        echo "  ⚠️ Password is adequate but could be stronger"
    fi
done

# Check network configuration
echo ""
echo "🌐 Checking network configuration..."
if [[ "$N8N_HOST" == "n8n.localhost" ]]; then
    echo "  ✅ Using localhost configuration"
    echo "  💡 Add '127.0.0.1 n8n.localhost' to /etc/hosts for local access"
else
    echo "  ✅ Using custom domain: $N8N_HOST"
    echo "  💡 Ensure DNS points to this server for external access"
fi

# Check ports
echo ""
echo "🚪 Checking port availability..."
PORTS=(80 443 5432 8080)
for port in "${PORTS[@]}"; do
    if ! netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo "  ✅ Port $port is available"
    else
        echo "  ⚠️ Port $port is already in use"
        netstat -tuln | grep ":$port "
    fi
done

# Check Docker daemon
echo ""
echo "🔧 Checking Docker daemon..."
if docker info &> /dev/null; then
    echo "  ✅ Docker daemon is running"
else
    echo "  ❌ Docker daemon is not accessible"
    echo "  💡 Try: sudo systemctl start docker"
    exit 1
fi

# Final recommendations
echo ""
echo "🎯 Setup Verification Complete!"
echo "================================"
echo ""
echo "Next steps:"
echo "1. Review and customize .env file if needed"
echo "2. Run: ./scripts/deploy.sh"
echo "3. Access n8n at: https://$N8N_HOST"
echo "4. Login with: $N8N_BASIC_AUTH_USER / (password from .env)"
echo ""
echo "Monitoring:"
echo "- Health check: ./scripts/health-check.sh"
echo "- View logs: docker compose logs -f"
echo "- Backup data: ./scripts/backup.sh"
echo ""
echo "Support URLs:"
echo "- n8n Documentation: https://docs.n8n.io/"
echo "- PostgreSQL Documentation: https://www.postgresql.org/docs/"
echo "- Traefik Documentation: https://doc.traefik.io/traefik/"
