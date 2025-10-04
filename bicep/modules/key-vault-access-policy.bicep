// Key Vault access policy module (must be deployed in same resource group as Key Vault)
@description('Name of the Key Vault')
param keyVaultName string

@description('Principal ID that needs access')
param principalId string

@description('Tenant ID')
param tenantId string

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Add access policy
resource accessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  parent: keyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: principalId
        permissions: {
          secrets: ['get']
        }
      }
    ]
  }
}

output success bool = true
