# Migrating from SQLite to PostgreSQL

This guide will help you migrate your existing n8n SQLite database to PostgreSQL while preserving all your workflows, credentials, and settings.

## Prerequisites

- Docker and Docker Compose installed
- Existing n8n deployment using SQLite
- Access to your current n8n data directory

## Step 1: Backup Your Current Data

Before starting the migration, create a complete backup of your existing n8n data:

```bash
# Stop the current n8n stack
docker compose down

# Create backup directory
mkdir -p backups/$(date +%Y%m%d_%H%M%S)

# Backup the entire n8n data volume
docker run --rm -v n8n_data:/data -v $(pwd)/backups/$(date +%Y%m%d_%H%M%S):/backup alpine tar czf /backup/n8n_data_backup.tar.gz -C /data .

# Also backup your docker-compose files
cp docker-compose.yml backups/$(date +%Y%m%d_%H%M%S)/
cp .env backups/$(date +%Y%m%d_%H%M%S)/ 2>/dev/null || echo "No .env file found"
```

## Step 2: Update Environment Variables

Add PostgreSQL configuration to your `.env` file:

```bash
# PostgreSQL Configuration
POSTGRES_DB=n8n
POSTGRES_USER=n8n
POSTGRES_PASSWORD=your_secure_password_here

# Replace with a strong password!
```

If you don't have a `.env` file, create one with your existing variables plus the PostgreSQL settings above.

## Step 3: Deploy PostgreSQL

The updated `docker-compose.yml` now includes PostgreSQL. Start only PostgreSQL first:

```bash
# Start only PostgreSQL to initialize the database
docker compose up -d postgres

# Wait for PostgreSQL to be ready
docker compose logs -f postgres
# Wait until you see "database system is ready to accept connections"
```

## Step 4: Export Data from SQLite

Export your existing data using n8n's built-in export functionality:

```bash
# Start n8n with the old SQLite configuration temporarily
# First, comment out the PostgreSQL environment variables in docker-compose.yml
# or create a temporary docker-compose file without them

# Export workflows
docker compose exec n8n n8n export:workflow --backup --output=/files/workflows_backup.json

# Export credentials (encrypted)
docker compose exec n8n n8n export:credentials --backup --output=/files/credentials_backup.json

# Alternatively, you can use the UI to export:
# 1. Access your n8n instance
# 2. Go to Settings > Import/Export
# 3. Export all workflows and credentials
```

## Step 5: Switch to PostgreSQL Configuration

Now update your n8n service to use PostgreSQL by ensuring these environment variables are set:

```yaml
environment:
  - DB_TYPE=postgresdb
  - DB_POSTGRESDB_HOST=postgres
  - DB_POSTGRESDB_PORT=5432
  - DB_POSTGRESDB_DATABASE=${POSTGRES_DB:-n8n}
  - DB_POSTGRESDB_USER=${POSTGRES_USER:-n8n}
  - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD:-n8n}
```

## Step 6: Start n8n with PostgreSQL

```bash
# Stop any running n8n instance
docker compose stop n8n

# Start n8n with PostgreSQL configuration
docker compose up -d

# Monitor the logs to ensure successful startup
docker compose logs -f n8n
```

## Step 7: Import Your Data

Import your backed up data into the new PostgreSQL-backed n8n instance:

```bash
# Import workflows
docker compose exec n8n n8n import:workflow --input=/files/workflows_backup.json

# Import credentials
docker compose exec n8n n8n import:credentials --input=/files/credentials_backup.json

# Or use the UI:
# 1. Access your n8n instance
# 2. Go to Settings > Import/Export
# 3. Import your exported files
```

## Step 8: Verify Migration

1. **Access n8n**: Open your n8n instance and verify all workflows are present
2. **Test workflows**: Run a few workflows to ensure they work correctly
3. **Check credentials**: Verify that all credentials are properly imported and functional
4. **Review executions**: Check that execution history is preserved (if exported/imported)

## Step 9: Clean Up

Once you've verified everything works correctly:

```bash
# Remove old SQLite database (optional, keep as backup)
# The SQLite file is typically located in the n8n_data volume at /home/node/.n8n/database.sqlite

# Remove temporary backup files from the container
docker compose exec n8n rm -f /files/workflows_backup.json /files/credentials_backup.json
```

## Troubleshooting

### Connection Issues
```bash
# Check PostgreSQL is running and healthy
docker compose ps postgres
docker compose logs postgres

# Test database connection
docker compose exec postgres psql -U n8n -d n8n -c "\l"
```

### Import Failures
```bash
# Check n8n logs for detailed error messages
docker compose logs n8n

# Ensure file permissions are correct
docker compose exec n8n ls -la /files/
```

### Performance Issues
```bash
# Monitor PostgreSQL performance
docker compose exec postgres psql -U n8n -d n8n -c "SELECT * FROM pg_stat_activity;"

# Check database size
docker compose exec postgres psql -U n8n -d n8n -c "SELECT pg_size_pretty(pg_database_size('n8n'));"
```

## Rollback Plan

If you need to rollback to SQLite:

1. Stop the stack: `docker compose down`
2. Restore your backup docker-compose.yml (without PostgreSQL config)
3. Restore the n8n_data volume from backup:
   ```bash
   docker run --rm -v n8n_data:/data -v $(pwd)/backups/BACKUP_DATE:/backup alpine tar xzf /backup/n8n_data_backup.tar.gz -C /data
   ```
4. Start with original configuration: `docker compose up -d`

## Benefits of PostgreSQL

After migration, you'll enjoy:

- **Better Performance**: PostgreSQL handles larger datasets more efficiently
- **Concurrent Access**: Multiple n8n instances can share the same database
- **Advanced Features**: Better backup/restore options, replication, and monitoring
- **Scalability**: Easier to scale as your automation needs grow
- **Data Integrity**: ACID compliance and better data consistency

## Maintenance

### Regular Backups
```bash
# Create PostgreSQL backup
docker compose exec postgres pg_dump -U n8n n8n > backup_$(date +%Y%m%d).sql

# Restore from backup
docker compose exec postgres psql -U n8n -d n8n < backup_YYYYMMDD.sql
```

### Monitoring
```bash
# Check database statistics
docker compose exec postgres psql -U n8n -d n8n -c "SELECT schemaname,tablename,n_tup_ins,n_tup_upd,n_tup_del FROM pg_stat_user_tables;"
```