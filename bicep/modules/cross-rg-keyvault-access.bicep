// Cross-resource-group Key Vault access policy module
@description('Name of the Key Vault')
param keyVaultName string

@description('Resource group containing the Key Vault')
param keyVaultResourceGroup string

@description('Principal ID that needs access')
param principalId string

@description('Tenant ID')
param tenantId string

// Reference the Key Vault in a different resource group
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  scope: resourceGroup(keyVaultResourceGroup)
  name: keyVaultName
}

// Create access policy in the Key Vault's resource group
module accessPolicy 'key-vault-access-policy.bicep' = {
  scope: resourceGroup(keyVaultResourceGroup)
  name: 'kv-access-${uniqueString(principalId)}'
  params: {
    keyVaultName: keyVaultName
    principalId: principalId
    tenantId: tenantId
  }
}

output success bool = true
