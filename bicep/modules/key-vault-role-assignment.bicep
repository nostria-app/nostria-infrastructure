// Key Vault role assignment module
param keyVaultName string
param principalId string
@description('Role definition ID to assign. Defaults to Key Vault Secrets User.')
param roleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6' // Default: Key Vault Secrets User

// Get a reference to the Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Assign role to the managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, roleDefinitionId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
