-- init.sql
-- PostgreSQL initialization script for n8n

-- Create non-root user for n8n application
-- Note: Password will be set via environment variable POSTGRES_NON_ROOT_PASSWORD
DO
$do$
BEGIN
   IF NOT EXISTS (
      SELECT FROM pg_catalog.pg_roles
      WHERE  rolname = 'n8n_user') THEN
      
      CREATE ROLE n8n_user LOGIN PASSWORD 'SecureN8nPass123!';
   END IF;
END
$do$;

-- Grant necessary permissions
GRANT CONNECT ON DATABASE n8n TO n8n_user;
GRANT USAGE ON SCHEMA public TO n8n_user;
GRANT CREATE ON SCHEMA public TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;

-- Create custom application schema (optional)
CREATE SCHEMA IF NOT EXISTS app_data;
GRANT USAGE ON SCHEMA app_data TO n8n_user;
GRANT CREATE ON SCHEMA app_data TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_data GRANT ALL ON SEQUENCES TO n8n_user;

-- Example custom table for Google Sheets replacement
CREATE TABLE IF NOT EXISTS app_data.workflow_data (
    id SERIAL PRIMARY KEY,
    workflow_id VARCHAR(255) NOT NULL,
    data_type VARCHAR(100) NOT NULL,
    data_json JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(workflow_id, data_type)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_workflow_data_workflow_id ON app_data.workflow_data(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_data_type ON app_data.workflow_data(data_type);
CREATE INDEX IF NOT EXISTS idx_workflow_data_created_at ON app_data.workflow_data(created_at);

-- Example view for simplified access
CREATE OR REPLACE VIEW app_data.latest_workflow_data AS
SELECT DISTINCT ON (workflow_id, data_type) 
    id, workflow_id, data_type, data_json, created_at, updated_at
FROM app_data.workflow_data
ORDER BY workflow_id, data_type, updated_at DESC;

-- Grant permissions on new objects
GRANT ALL ON app_data.workflow_data TO n8n_user;
GRANT ALL ON SEQUENCE app_data.workflow_data_id_seq TO n8n_user;
GRANT SELECT ON app_data.latest_workflow_data TO n8n_user;

COMMENT ON TABLE app_data.workflow_data IS 'Centralized storage for workflow data, replacing Google Sheets';
COMMENT ON VIEW app_data.latest_workflow_data IS 'Latest version of each workflow data entry';
