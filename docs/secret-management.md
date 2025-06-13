# Nostria Infrastructure Secret Management

This document explains how to securely manage sensitive configuration values like `PRIVATE_VAPID_KEY` and `NOTIFICATION_API_KEY` for the Nostria infrastructure.

## Solution Overview

The infrastructure uses **Azure Key Vault** to securely store and manage secrets. This follows Azure security best practices by:

1. Storing secrets in Azure Key Vault instead of in code
2. Using Managed Identity for secure access
3. Using Key Vault references in App Service configuration
4. **Manual secret management** separate from infrastructure deployment

## Architecture

1. **Infrastructure Deployment** creates the Key Vault and configures the notification app with Key Vault references
2. **Manual Secret Management** adds/updates secrets in Key Vault after deployment
3. **Runtime Access** - the notification app automatically retrieves secrets from Key Vault using Managed Identity

## Infrastructure Changes

### New Resources Added

1. **Key Vault** (`modules/key-vault.bicep`)
   - Stores application secrets securely
   - Configured with RBAC authorization
   - Named: `nostria-kv-{uniqueString}`

2. **Key Vault Secrets** (`modules/key-vault-secret.bicep`)
   - `private-vapid-key`: Stores the PRIVATE_VAPID_KEY
   - `notification-api-key`: Stores the NOTIFICATION_API_KEY

3. **Key Vault Role Assignment** (`modules/key-vault-role-assignment.bicep`)
   - Grants the notification app's Managed Identity access to Key Vault secrets
   - Uses the "Key Vault Secrets User" role

### Modified Resources

1. **Main Template** (`main.bicep`)
   - Added Key Vault deployment
   - Updated notification app configuration to use Key Vault references
   - Removed secret parameters (secrets are managed separately)

2. **Deployment Script** (`deploy-main.ps1`)
   - Simplified to focus on infrastructure deployment only
   - Removed secret input handling
   - Added warning about manual secret management

## Deployment Process

### Step 1: Deploy Infrastructure

```powershell
.\scripts\deploy-main.ps1
```

This creates:
- Key Vault (`nostria-kv-{uniqueString}`)
- Notification app configured with Key Vault references
- Managed Identity with Key Vault access permissions

⚠️ **Important**: The notification app will not function until secrets are added to Key Vault.

### Step 2: Add Secrets to Key Vault

After infrastructure deployment, use the secret management script:

```powershell
# List current secrets (will be empty initially)
.\scripts\manage-keyvault-secrets.ps1 -Action list

# Add private VAPID key
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key

# Add notification API key
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName notification-api-key

# Verify secrets were added
.\scripts\manage-keyvault-secrets.ps1 -Action list
```

## Secret Management Script

The `manage-keyvault-secrets.ps1` script provides easy management of notification secrets:

### List Secrets
```powershell
.\scripts\manage-keyvault-secrets.ps1 -Action list
```

### Add/Update Secrets
```powershell
# Add private VAPID key (will prompt for value)
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key

# Add notification API key (will prompt for value)
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName notification-api-key

# Set secret with value from variable
$secretValue = ConvertTo-SecureString "your-secret-value" -AsPlainText -Force
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key -SecretValue $secretValue
```

### Check Secret Existence
```powershell
# Check if secrets exist (values are hidden for security)
.\scripts\manage-keyvault-secrets.ps1 -Action get -SecretName private-vapid-key
.\scripts\manage-keyvault-secrets.ps1 -Action get -SecretName both
```

### Delete Secrets (Use with caution)
```powershell
# Delete a specific secret
.\scripts\manage-keyvault-secrets.ps1 -Action delete -SecretName private-vapid-key

# Delete both secrets (will prompt for confirmation)
.\scripts\manage-keyvault-secrets.ps1 -Action delete -SecretName both
```

## CI/CD Pipeline Integration

For automated deployments, you can integrate secret management into your pipelines:

### Azure DevOps Pipeline

```yaml
# Infrastructure deployment stage
- stage: DeployInfrastructure
  jobs:
  - job: DeployBicep
    steps:
    - task: AzureResourceManagerTemplateDeployment@3
      displayName: 'Deploy Infrastructure'
      inputs:
        deploymentScope: 'Resource Group'
        azureResourceManagerConnection: 'your-service-connection'
        resourceGroupName: 'nostria-global'
        location: 'West Europe'
        templateLocation: 'Linked artifact'
        csmFile: 'bicep/main.bicep'
        csmParametersFile: 'bicep/main.bicepparam'

# Secret management stage (runs after infrastructure)
- stage: ManageSecrets
  dependsOn: DeployInfrastructure
  jobs:
  - job: UpdateSecrets
    steps:
    - task: AzurePowerShell@5
      displayName: 'Update Key Vault Secrets'
      inputs:
        azureSubscription: 'your-service-connection'
        ScriptType: 'FilePath'
        ScriptPath: 'scripts/manage-keyvault-secrets.ps1'
        ScriptArguments: '-Action set -SecretName private-vapid-key -SecretValue (ConvertTo-SecureString "$(PRIVATE_VAPID_KEY)" -AsPlainText -Force)'
        azurePowerShellVersion: 'LatestVersion'
    
    - task: AzurePowerShell@5
      displayName: 'Update Notification API Key'
      inputs:
        azureSubscription: 'your-service-connection'
        ScriptType: 'FilePath'
        ScriptPath: 'scripts/manage-keyvault-secrets.ps1'
        ScriptArguments: '-Action set -SecretName notification-api-key -SecretValue (ConvertTo-SecureString "$(NOTIFICATION_API_KEY)" -AsPlainText -Force)'
        azurePowerShellVersion: 'LatestVersion'
```

### GitHub Actions Workflow

```yaml
name: Deploy Infrastructure and Manage Secrets

on:
  push:
    branches: [main]

jobs:
  deploy-infrastructure:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Azure Login
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Deploy Infrastructure
      uses: azure/arm-deploy@v1
      with:
        subscriptionId: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
        resourceGroupName: nostria-global
        template: bicep/main.bicep
        parameters: bicep/main.bicepparam
    
    - name: Update Key Vault Secrets
      uses: azure/powershell@v1
      with:
        inlineScript: |
          .\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key -SecretValue (ConvertTo-SecureString "${{ secrets.PRIVATE_VAPID_KEY }}" -AsPlainText -Force)
          .\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName notification-api-key -SecretValue (ConvertTo-SecureString "${{ secrets.NOTIFICATION_API_KEY }}" -AsPlainText -Force)
        azPSVersion: "latest"
```

## How It Works

1. **Infrastructure Deployment**: Creates Key Vault and configures app with Key Vault references
2. **Manual Secret Management**: Add secrets to Key Vault using the management script or Azure portal
3. **App Configuration**: The notification app is pre-configured with Key Vault references:
   ```
   PRIVATE_VAPID_KEY = @Microsoft.KeyVault(VaultName=nostria-kv-xyz;SecretName=private-vapid-key)
   NOTIFICATION_API_KEY = @Microsoft.KeyVault(VaultName=nostria-kv-xyz;SecretName=notification-api-key)
   ```
4. **Access Control**: The notification app's Managed Identity has "Key Vault Secrets User" role
5. **Runtime**: App Service automatically retrieves secret values from Key Vault when needed

## Security Benefits

- ✅ **Complete separation of infrastructure and secrets**
- ✅ **No secrets in source code or deployment logs**
- ✅ **Automatic secret rotation support**
- ✅ **Audit logging of secret access**
- ✅ **Fine-grained access control**
- ✅ **Managed Identity authentication**
- ✅ **Secrets managed independently of deployments**

## Managing Secrets After Deployment

### Using the Management Script (Recommended)

```powershell
# List all secrets
.\scripts\manage-keyvault-secrets.ps1 -Action list

# Add or update a secret (will prompt for value)
.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key

# Check if secrets exist
.\scripts\manage-keyvault-secrets.ps1 -Action get -SecretName both
```

### Using Azure Portal
1. Navigate to the Key Vault resource (`nostria-kv-{uniqueString}`)
2. Go to "Secrets" section
3. Click "+ Generate/Import" to add a new secret
4. Use exact names: `private-vapid-key`, `notification-api-key`

### Using Azure CLI
```bash
# Find the Key Vault name
az keyvault list --resource-group nostria-global --query "[?starts_with(name, 'nostria-kv')].name" -o tsv

# Set secrets
az keyvault secret set --vault-name "nostria-kv-xyz" --name "private-vapid-key" --value "your-private-key"
az keyvault secret set --vault-name "nostria-kv-xyz" --name "notification-api-key" --value "your-api-key"

# List secrets
az keyvault secret list --vault-name "nostria-kv-xyz" --query "[].name" -o tsv
```

### Using Azure PowerShell
```powershell
# Find the Key Vault
$keyVault = Get-AzKeyVault -ResourceGroupName "nostria-global" | Where-Object { $_.VaultName -like "nostria-kv-*" }

# Set secrets
Set-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name "private-vapid-key" -SecretValue (ConvertTo-SecureString "your-private-key" -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName $keyVault.VaultName -Name "notification-api-key" -SecretValue (ConvertTo-SecureString "your-api-key" -AsPlainText -Force)

# List secrets
Get-AzKeyVaultSecret -VaultName $keyVault.VaultName | Select-Object Name, Updated
```

## Troubleshooting

### App can't access Key Vault
- Verify the Managed Identity has "Key Vault Secrets User" role
- Check Key Vault access policies if not using RBAC
- Ensure the app is configured with correct Key Vault references

### Secrets not found after deployment
- The infrastructure creates an empty Key Vault
- You must manually add secrets using the management script or Azure portal
- Use exact secret names: `private-vapid-key`, `notification-api-key`

### Key Vault name conflicts
- Key Vault names are globally unique
- The template uses `uniqueString(resourceGroup().id)` to ensure uniqueness
- If deployment fails due to name conflict, delete existing Key Vault or change resource group

### App returns errors about missing configuration
- Check that secrets exist in Key Vault: `.\scripts\manage-keyvault-secrets.ps1 -Action list`
- Verify secret names match exactly: `private-vapid-key`, `notification-api-key`
- Check app logs for Key Vault access errors

## Workflow Summary

1. **Deploy Infrastructure**: `.\scripts\deploy-main.ps1`
2. **Add Secrets**: `.\scripts\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key`
3. **Verify Setup**: `.\scripts\manage-keyvault-secrets.ps1 -Action list`
4. **Test App**: The notification app should now function correctly

## Migration from Old Configuration

If you previously had secrets hardcoded or in configuration:

1. **Deploy new infrastructure** using `.\scripts\deploy-main.ps1`
2. **Add secrets to Key Vault** using the management script
3. **Verify app functionality** after adding secrets
4. **Remove old secrets** from any configuration files
5. **Update CI/CD pipelines** to use Key Vault secret management
6. **Rotate secrets** in Key Vault for security

## File References

- `scripts/manage-keyvault-secrets.ps1` - Secret management script
- `scripts/deploy-main.ps1` - Infrastructure deployment script
- `bicep/modules/key-vault.bicep` - Key Vault module
- `bicep/modules/key-vault-role-assignment.bicep` - RBAC for Key Vault access
- `docs/secret-management.md` - This documentation
