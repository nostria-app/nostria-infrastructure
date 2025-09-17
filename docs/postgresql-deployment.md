# PostgreSQL Deployment Guide

This guide explains how to deploy Azure Database for PostgreSQL Flexible Server with your Nostria infrastructure.

## What was added

1. **PostgreSQL Flexible Server module** (`bicep/modules/postgresql.bicep`)
   - Configures a PostgreSQL 16 server with security best practices
   - Enables SSL enforcement and Azure AD authentication
   - Creates the main database for your application

2. **Connection string automation** (`bicep/modules/postgresql-connection-secret.bicep`)
   - Automatically generates the PostgreSQL connection string
   - Stores it securely in Azure Key Vault
   - Makes it available to your applications via Key Vault reference

3. **Application integration**
   - Added `POSTGRESQL_CONNECTION_STRING` environment variable to the service app
   - The connection string is automatically retrieved from Key Vault

## Deployment

### Option 1: Using the deployment script with password parameter

```powershell
# Create a secure string for the password
$password = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force

# Deploy with PostgreSQL
.\scripts\deploy-main.ps1 -PostgreSQLAdminPassword $password
```

### Option 2: Using Azure CLI directly

```bash
# Deploy and provide password when prompted
az deployment group create \
  --resource-group nostria-global \
  --template-file bicep/main.bicep \
  --parameters @bicep/main.bicepparam \
  --parameters postgresqlAdminPassword='YourSecurePassword123!'
```

### Option 3: Store password in Key Vault first (recommended for production)

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
  --parameters @bicep/main.bicepparam \
  --parameters postgresqlAdminPassword="@Microsoft.KeyVault(VaultName=nostria-kv;SecretName=postgresql-admin-password)"
```

## Connection Details

After deployment, your applications will have access to:
- **Environment Variable**: `POSTGRESQL_CONNECTION_STRING`
- **Connection String Format**: `postgresql://nostria_admin:***@nostria-postgres.postgres.database.azure.com:5432/nostria?sslmode=require`

## Security Features

- SSL/TLS encryption enforced
- Azure AD authentication enabled
- Connection string stored securely in Key Vault
- Firewall configured to allow Azure services
- Managed identity used for Key Vault access

## Configuration Options

The PostgreSQL server is deployed with these default settings:
- **Version**: PostgreSQL 16
- **SKU**: Standard_B2ms (Burstable tier)
- **Storage**: 128GB with auto-grow enabled
- **Backup**: 7-day retention, local redundancy
- **High Availability**: Disabled (can be enabled by changing the parameter)

You can modify these settings in the `main.bicep` file in the `postgresqlServer` module parameters.

## Troubleshooting

1. **Password Requirements**: PostgreSQL requires a password with at least 8 characters including uppercase, lowercase, and numbers.

2. **Connection Issues**: Ensure your application is running in Azure or the PostgreSQL firewall is configured to allow your IP.

3. **Key Vault Access**: Verify that your applications have the "Key Vault Secrets User" role assigned (already configured for the service app).

## Manual Tasks

The connection string is automatically generated and stored in Key Vault during deployment, so no manual intervention is required for basic setup. However, you may want to:

1. Create additional database users for specific applications
2. Configure additional firewall rules if needed
3. Set up monitoring and alerting
4. Configure backup policies beyond the default settings