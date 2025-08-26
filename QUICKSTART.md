# Quick Start Guide - n8n Docker Setup

## 🚀 5-Minute Setup

### 1. Prerequisites Check
```bash
# Verify your system
lsb_release -a    # Should show Ubuntu 25.04
nvidia-smi        # Should show your RTX 2070
df -h             # Check available disk space
```

### 2. Install Dependencies
```bash
cd /DATA/Work/Projects/N8N/compose
./scripts/install-dependencies.sh
```
*Note: If Docker was just installed, log out and back in before continuing.*

### 3. Verify Setup
```bash
./scripts/verify-setup.sh
```

### 4. Deploy Stack
```bash
./scripts/deploy.sh
```

### 5. Access n8n
- **URL**: https://n8n.localhost
- **Username**: admin
- **Password**: SecureN8nAdminPass123! *(change this in .env file)*

### 6. Add to hosts file (for local access)
```bash
echo "127.0.0.1 n8n.localhost traefik.localhost" | sudo tee -a /etc/hosts
```

## 🔧 Daily Operations

### View Logs
```bash
docker compose logs -f n8n        # n8n application logs
docker compose logs -f postgres   # Database logs
docker compose logs -f traefik    # Proxy logs
```

### Backup Data
```bash
./scripts/backup.sh
```

### Health Check
```bash
./scripts/health-check.sh
```

### Stop/Start Services
```bash
docker compose down           # Stop all services
docker compose up -d          # Start all services
docker compose restart n8n    # Restart just n8n
```

## 🛠️ Customization

### Change Domain (for production)
1. Edit `.env` file:
   ```bash
   DOMAIN_NAME=yourdomain.com
   N8N_HOST=n8n.yourdomain.com
   ACME_EMAIL=admin@yourdomain.com
   ```

2. Update DNS records to point to your server

3. Redeploy:
   ```bash
   docker compose down
   docker compose up -d
   ```

### Update Passwords
1. Edit `.env` file with new passwords
2. Update database:
   ```bash
   docker exec -it n8n-postgres psql -U postgres -c "ALTER USER n8n_user PASSWORD 'new_password';"
   ```
3. Restart n8n:
   ```bash
   docker compose restart n8n
   ```

## 🔍 Troubleshooting

### Common Issues

#### "Cannot connect to Docker daemon"
```bash
sudo systemctl start docker
sudo usermod -aG docker $USER
# Log out and back in
```

#### "Address already in use"
```bash
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443
# Stop conflicting services or change ports in docker-compose.yml
```

#### "n8n not accessible"
```bash
docker compose ps                    # Check service status
docker compose logs n8n              # Check n8n logs
curl -k https://localhost            # Test connectivity
```

#### Database connection errors
```bash
docker compose logs postgres         # Check database logs
docker exec n8n-postgres psql -U postgres -l  # Test database access
```

### Get Help
- Check main README.md for detailed troubleshooting
- View logs: `docker compose logs -f`
- Reset everything: `docker compose down -v && docker compose up -d`

## 📊 Monitoring URLs

- **n8n Interface**: https://n8n.localhost
- **Traefik Dashboard**: http://localhost:8080
- **PostgreSQL**: Connect via n8n or database client on localhost:5432

---

For complete documentation, see the main [README.md](README.md) file.
