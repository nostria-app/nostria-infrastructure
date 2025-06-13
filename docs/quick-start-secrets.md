# Quick Start: Secret Management for Nostria Infrastructure

This guide shows you how to deploy the Nostria infrastructure and set up notification secrets using the new Key Vault-based approach.

## Prerequisites

- Azure PowerShell module installed
- Azure CLI (optional)
- Authenticated to Azure (`Connect-AzAccount`)
- Contributor access to the target resource group

## Step 1: Deploy Infrastructure

```powershell
# Navigate to the scripts directory
cd f:\src\github\nostria\nostria-infrastructure\scripts

# Deploy the infrastructure (creates Key Vault but no secrets)
.\deploy-main.ps1
```

This creates:
- All Nostria infrastructure components
- Key Vault (`nostria-kv-{uniqueString}`)
- Notification app configured to read from Key Vault
- Managed Identity with Key Vault permissions

⚠️ **The notification app will not work until secrets are added to Key Vault**

## Step 2: Add Secrets to Key Vault

```powershell
# Add the private VAPID key
.\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key
# (You'll be prompted to enter the secret value securely)

# Add the notification API key
.\manage-keyvault-secrets.ps1 -Action set -SecretName notification-api-key
# (You'll be prompted to enter the secret value securely)
```

## Step 3: Verify Setup

```powershell
# List secrets in Key Vault
.\manage-keyvault-secrets.ps1 -Action list

# Check that secrets exist (values hidden for security)
.\manage-keyvault-secrets.ps1 -Action get -SecretName both
```

## Step 4: Test Notification App

Your notification app should now be functional with the secrets automatically retrieved from Key Vault.

## Updating Secrets Later

```powershell
# Update a secret (will prompt for new value)
.\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key

# Or update from a variable
$newSecret = ConvertTo-SecureString "new-secret-value" -AsPlainText -Force
.\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key -SecretValue $newSecret
```

## Key Benefits

✅ **Secure**: Secrets stored in Azure Key Vault, not in code  
✅ **Separated**: Infrastructure deployment separate from secret management  
✅ **Auditable**: All secret access logged by Azure  
✅ **Rotatable**: Update secrets without redeploying infrastructure  
✅ **Automated**: App automatically retrieves current secret values  

## Troubleshooting

If the notification app isn't working:

1. **Check secrets exist**: `.\manage-keyvault-secrets.ps1 -Action list`
2. **Verify secret names**: Must be exactly `private-vapid-key` and `notification-api-key`
3. **Check app logs** in Azure Portal for Key Vault access errors
4. **Verify permissions**: Managed Identity should have "Key Vault Secrets User" role

## Next Steps

- Set up secret rotation policies in Key Vault
- Configure monitoring and alerts for secret access
- Update CI/CD pipelines to manage secrets automatically
- Document your specific secret values in your organization's secure location

For detailed information, see `docs/secret-management.md`.
