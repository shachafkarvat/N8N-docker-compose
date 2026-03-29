name: n8n

services:
  n8n:
    image: ${ecr_repo_url}:${ecr_image_tag}
    restart: unless-stopped
%{ if use_alb ~}
    ports:
      - "5678:5678"
%{ endif ~}
    environment:
      - N8N_HOST=${fqdn}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${fqdn}/
      - NODE_ENV=production
      - GENERIC_TIMEZONE=${timezone}
      - TZ=${timezone}
      - N8N_RUNNERS_ENABLED=true
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      - N8N_PROXY_HOPS=${n8n_proxy_hops}
      - N8N_TRUST_PROXY=true
      - NODE_OPTIONS=--max-old-space-size=1536
      - NODE_FUNCTION_ALLOW_EXTERNAL=cheerio
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=$${N8N_ENCRYPTION_KEY}
    volumes:
      - /mnt/efs/n8n-data:/home/node/.n8n
      - /mnt/efs/local-files:/files
    networks:
      - n8n_net
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget -qO- http://localhost:5678/healthz || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 60s

%{ if !use_alb ~}
  edge:
    image: nginx:1.27-alpine
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/n8n/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - /run/n8n/tls:/run/n8n/tls:ro
    networks:
      - n8n_net
    depends_on:
      n8n:
        condition: service_healthy
%{ endif ~}

  postgres:
    image: postgres:16-alpine
    restart: unless-stopped
    user: "999:999"
    environment:
      POSTGRES_DB: n8n
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - /mnt/efs/postgres-data:/var/lib/postgresql/data
    networks:
      - n8n_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d n8n"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes: {}

networks:
  n8n_net:
    driver: bridge