// RBAC role assignment module for Key Vault access (same scope)
@description('Principal ID that needs access')
param principalId string

@description('Key Vault name')
param keyVaultName string

@description('Role definition ID for Key Vault Secrets User')
param roleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User

@description('Whether to create the role assignment (set to false if it already exists)')
param createRoleAssignment bool = true

// Reference the existing Key Vault in the same resource group
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Create role assignment for Key Vault access (conditional)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createRoleAssignment) {
  scope: keyVault
  name: guid(keyVault.id, principalId, roleDefinitionId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = createRoleAssignment ? roleAssignment.id : 'skipped'
output success bool = true
