# PostgreSQL Deployment Guide

This guide explains how to deploy Azure Database for PostgreSQL Flexible Server with your Nostria infrastructure.

## PostgreSQL is Optional

By default, PostgreSQL deployment is **disabled** to allow faster deployments and reduced costs during development. You can enable PostgreSQL deployment when needed using the `-DeployPostgreSQL` switch.

## What was added

1. **PostgreSQL Flexible Server module** (`bicep/modules/postgresql.bicep`)
   - Configures a PostgreSQL 17 server with security best practices
   - Enables SSL enforcement and Azure AD authentication
   - Creates the main database for your application

2. **Connection string automation** (`bicep/modules/postgresql-connection-secret.bicep`)
   - Automatically generates the PostgreSQL connection string
   - Stores it securely in Azure Key Vault
   - Makes it available to your applications via Key Vault reference

3. **Application integration**
   - Added `POSTGRESQL_CONNECTION_STRING` environment variable to the service app (only when PostgreSQL is deployed)
   - The connection string is automatically retrieved from Key Vault

## Deployment

### Option 1: Deploy without PostgreSQL (Default - Faster)

```powershell
# Deploy infrastructure without PostgreSQL
.\scripts\deploy-main.ps1
```

### Option 2: Deploy with PostgreSQL

```powershell
# Create a secure string for the password
$password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

# Deploy with PostgreSQL
.\scripts\deploy-main.ps1 -DeployPostgreSQL -PostgreSQLAdminPassword $password
```

### Option 3: Using Azure CLI directly with PostgreSQL

```bash
# Deploy and enable PostgreSQL
az deployment group create \
  --resource-group nostria-global \
  --template-file bicep/main.bicep \
  --parameters deployPostgreSQL=true postgresqlAdminPassword='YourSecurePassword123!'
```

### Option 4: Store password in Key Vault first (recommended for production)

```powershell
# Store the password in Key Vault first
az keyvault secret set \
  --vault-name "nostria-kv" \
  --name "postgresql-admin-password" \
  --value "YourSecurePassword123!"

# Then reference it in deployment
az deployment group create \
  --resource-group nostria-global \
  --template-file bicep/main.bicep \
  --parameters deployPostgreSQL=true postgresqlAdminPassword="@Microsoft.KeyVault(VaultName=nostria-kv;SecretName=postgresql-admin-password)"
```

## Connection Details

After deployment **with PostgreSQL enabled**, your applications will have access to:
- **Environment Variable**: `POSTGRESQL_CONNECTION_STRING`
- **Connection String Format**: `postgresql://nostria_admin:***@nostria-postgres.postgres.database.azure.com:5432/nostria?sslmode=require`

When PostgreSQL is **not deployed**, the `POSTGRESQL_CONNECTION_STRING` environment variable will not be set on the service app.

## Security Features

- SSL/TLS encryption enforced
- Azure AD authentication enabled
- Connection string stored securely in Key Vault
- Firewall configured to allow Azure services
- Managed identity used for Key Vault access

## Configuration Options

The PostgreSQL server is deployed with these default settings:
- **Version**: PostgreSQL 17
- **SKU**: Standard_B1ms (Burstable tier)
- **Storage**: 32GB with auto-grow enabled
- **Backup**: 7-day retention, local redundancy
- **High Availability**: Disabled (can be enabled by changing the parameter)

You can modify these settings in the `main.bicep` file in the `postgresqlServer` module parameters.

## Adding PostgreSQL to Existing Deployment

If you initially deployed without PostgreSQL and want to add it later:

1. Redeploy with the `-DeployPostgreSQL` switch:
   ```powershell
   $password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force
   .\scripts\deploy-main.ps1 -DeployPostgreSQL -PostgreSQLAdminPassword $password
   ```

2. The deployment will add:
   - PostgreSQL Flexible Server
   - Connection string secret in Key Vault
   - `POSTGRESQL_CONNECTION_STRING` environment variable to the service app

## Troubleshooting

1. **Password Requirements**: PostgreSQL requires a password with at least 8 characters including uppercase, lowercase, and numbers.

2. **Connection Issues**: Ensure your application is running in Azure or the PostgreSQL firewall is configured to allow your IP.

3. **Key Vault Access**: Verify that your applications have the "Key Vault Secrets User" role assigned (already configured for the service app).

4. **Missing Environment Variable**: If `POSTGRESQL_CONNECTION_STRING` is missing from your service app, ensure you deployed with `-DeployPostgreSQL` switch.

## Manual Tasks

When PostgreSQL is deployed, the connection string is automatically generated and stored in Key Vault, so no manual intervention is required for basic setup. However, you may want to:

1. Create additional database users for specific applications
2. Configure additional firewall rules if needed
3. Set up monitoring and alerting
4. Configure backup policies beyond the default settings