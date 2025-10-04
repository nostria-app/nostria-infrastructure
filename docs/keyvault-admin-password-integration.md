# Azure Key Vault Integration for Blossom Admin Password

This document explains how the Nostria infrastructure integrates with Azure Key Vault to securely manage the Blossom admin password.

## Overview

The infrastructure has been configured to store and retrieve the Blossom admin password from Azure Key Vault, providing:

- **Security**: Admin password is stored encrypted in Key Vault
- **Automation**: Password is automatically injected into containers at runtime
- **Rotation**: Easy password rotation without redeploying containers
- **Audit**: Full audit trail of password access

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────────┐
│   Azure         │    │  App Service     │    │   Container         │
│   Key Vault     │───▶│  Environment     │───▶│   Application       │
│                 │    │  Variables       │    │   (config.yml)      │
└─────────────────┘    └──────────────────┘    └─────────────────────┘
```

## How It Works

### 1. Key Vault Secret Storage
- The Blossom admin password is stored as a secret named `blossom-admin-password` in the `nostria-kv` Key Vault
- The secret is created during the main infrastructure deployment

### 2. App Service Integration with RBAC
- Each media server container app has a system-assigned managed identity
- The managed identity is automatically granted the `Key Vault Secrets User` RBAC role
- App settings include a Key Vault reference: `@Microsoft.KeyVault(VaultName=nostria-kv;SecretName=blossom-admin-password)`
- **Important**: The Key Vault uses RBAC authorization instead of access policies

### 3. Configuration Injection
- The `config/media/config.yml` file uses environment variable substitution: `password: "${BLOSSOM_ADMIN_PASSWORD}"`
- Azure App Service automatically resolves the Key Vault reference and sets the `BLOSSOM_ADMIN_PASSWORD` environment variable
- The container application reads the config.yml file with the resolved password value

## Files Modified

### Infrastructure Files
- `bicep/main.bicep` - Added Key Vault secret creation
- `bicep/region.bicep` - Added Key Vault name parameter and app setting
- `bicep/modules/container-app.bicep` - Added Key Vault access permissions
- `bicep/region.bicepparam` - Added Key Vault name parameter

### Configuration Files
- `config/media/config.yml` - Updated dashboard password to use environment variable

### Scripts
- `scripts/deploy-with-keyvault-admin-password.ps1` - Deployment script with Key Vault integration

## Deployment

### Option 1: Using the Deployment Script
```powershell
.\scripts\deploy-with-keyvault-admin-password.ps1 `
    -ResourceGroupName "your-resource-group" `
    -Location "East US" `
    -BlossomAdminPassword "your-secure-password" `
    -CurrentRegion "eu"
```

### Option 2: Manual Deployment
```bash
# 1. Deploy main infrastructure with admin password
az deployment group create \
    --resource-group your-resource-group \
    --template-file bicep/main.bicep \
    --parameters blossomAdminPassword="your-secure-password"

# 2. Deploy region-specific resources
az deployment group create \
    --resource-group your-resource-group \
    --template-file bicep/region.bicep \
    --parameters bicep/region.bicepparam \
    --parameters currentRegion="eu"
```

## Password Rotation

To rotate the admin password:

1. Update the Key Vault secret:
```bash
az keyvault secret set \
    --vault-name nostria-kv \
    --name blossom-admin-password \
    --value "new-secure-password"
```

2. Restart the container apps to pick up the new value:
```bash
az webapp restart --resource-group your-resource-group --name nostria-eu-mibo
```

## Security Features

### Managed Identity
- Each container app uses Azure Managed Identity
- No connection strings or keys stored in application code
- Automatic credential rotation by Azure

### Key Vault Access Policy
- Principle of least privilege - only "get" permission on secrets
- Scoped to specific container app identities
- Audit logs available in Azure Monitor

### Secure Configuration
- Password never stored in plaintext in configuration files
- Environment variable injection happens at runtime
- Configuration template stored in source control safely

## Troubleshooting

### Check Key Vault Secret
```bash
az keyvault secret show \
    --vault-name nostria-kv \
    --name blossom-admin-password
```

### Verify RBAC Role Assignments
```powershell
# Check if the web app has the Key Vault Secrets User role
$webApp = Get-AzWebApp -Name "nostria-us-mibo"
$keyVault = Get-AzKeyVault -VaultName "nostria-kv"
Get-AzRoleAssignment -ObjectId $webApp.Identity.PrincipalId -Scope $keyVault.ResourceId
```

### Fix RBAC Permissions
If you encounter "AccessToKeyVaultDenied" errors:
```powershell
# Run the automated fix script
.\scripts\fix-keyvault-rbac.ps1

# Or manually assign the role
$webApp = Get-AzWebApp -Name "your-app-name"
$keyVault = Get-AzKeyVault -VaultName "nostria-kv"
New-AzRoleAssignment -ObjectId $webApp.Identity.PrincipalId -RoleDefinitionName "Key Vault Secrets User" -Scope $keyVault.ResourceId
```

### Check Container Logs
```bash
az webapp log tail \
    --resource-group your-resource-group \
    --name nostria-eu-mibo
```

## Best Practices

1. **Use Strong Passwords**: Generate cryptographically secure passwords
2. **Regular Rotation**: Rotate passwords periodically
3. **Monitor Access**: Review Key Vault access logs regularly
4. **Backup Secrets**: Ensure Key Vault has appropriate backup and recovery policies
5. **Environment Separation**: Use separate Key Vaults for different environments (dev/staging/prod)

## Environment Variable Substitution

The Blossom application must support environment variable substitution in YAML files. The syntax `${VARIABLE_NAME}` in the config.yml file will be replaced with the actual environment variable value at runtime.

If your Blossom application doesn't support this natively, you may need to:
1. Add a startup script that processes the config file
2. Use an init container to substitute variables
3. Modify the application to support environment variable expansion

## Related Documentation

- [Azure Key Vault Documentation](https://docs.microsoft.com/en-us/azure/key-vault/)
- [App Service Key Vault Integration](https://docs.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
- [Azure Managed Identity](https://docs.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/)