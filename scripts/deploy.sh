#!/bin/bash
# scripts/deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🚀 Deploying n8n Docker Stack..."

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please run install-dependencies.sh first."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose not found. Please run install-dependencies.sh first."
    exit 1
fi

# Check environment file
if [[ ! -f "$PROJECT_DIR/.env" ]]; then
    echo "❌ Environment file not found. Please copy .env.example to .env and customize."
    exit 1
fi

# Create necessary directories
mkdir -p "$PROJECT_DIR/config/dynamic"

# Generate self-signed certificates for local development
if [[ ! -f "$PROJECT_DIR/config/dynamic/tls.yml" ]]; then
    echo "📄 Generating self-signed certificates for local development..."
    cat > "$PROJECT_DIR/config/dynamic/tls.yml" << EOF
tls:
  certificates:
    - certFile: /etc/traefik/dynamic/localhost.crt
      keyFile: /etc/traefik/dynamic/localhost.key
      stores:
        - default
  stores:
    default:
      defaultCertificate:
        certFile: /etc/traefik/dynamic/localhost.crt
        keyFile: /etc/traefik/dynamic/localhost.key
EOF

    # Generate certificate
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$PROJECT_DIR/config/dynamic/localhost.key" \
        -out "$PROJECT_DIR/config/dynamic/localhost.crt" \
        -subj "/C=US/ST=Local/L=Local/O=Local/OU=Local/CN=localhost" \
        -addext "subjectAltName=DNS:localhost,DNS:n8n.localhost,DNS:traefik.localhost,IP:127.0.0.1"
fi

# Pull latest images
echo "⬇️ Pulling latest Docker images..."
if ! docker compose pull; then
    echo "❌ Failed to pull images. Continuing with existing images..."
fi

# Deploy stack
echo "🏗️ Starting services..."
if ! docker compose up -d; then
    echo "❌ Failed to start services. Checking for issues..."
    docker compose logs --tail=20
    exit 1
fi

# Wait for services to be healthy
echo "⏳ Waiting for services to start..."
sleep 30

# Check service status
echo "🔍 Checking service status..."
docker compose ps

# Verify connectivity
echo "🌐 Verifying connectivity..."
for i in {1..10}; do
    if curl -k -s -f https://n8n.localhost > /dev/null 2>&1; then
        echo "✅ n8n is accessible at https://n8n.localhost"
        break
    elif curl -k -s -f https://localhost > /dev/null 2>&1; then
        echo "✅ n8n is accessible at https://localhost"
        break
    else
        echo "⏳ Attempt $i/10: n8n not ready yet..."
        sleep 10
    fi
    
    if [[ $i -eq 10 ]]; then
        echo "⚠️ n8n may still be starting up. Check logs:"
        echo "   docker compose logs n8n"
        echo "   docker compose logs traefik"
    fi
done

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "Access URLs:"
echo "  - n8n: https://n8n.localhost"
echo "  - Traefik Dashboard: http://localhost:8080"
echo ""
echo "Default credentials (change these!):"
echo "  - Username: admin"
echo "  - Password: (check your .env file)"
echo ""
echo "Useful commands:"
echo "  - View logs: docker compose logs -f"
echo "  - Stop services: docker compose down"
echo "  - Restart: docker compose restart"
echo "  - Update: docker compose pull && docker compose up -d"
