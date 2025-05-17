// filepath: c:\src\github\nostria\nostria-infrastructure\bicep\modules\role-assignment.bicep
param storageAccountName string
param principalId string
@description('Role definition ID to assign. Defaults to Storage File Data SMB Share Contributor.')
param roleDefinitionId string = 'b24988ac-6180-42a0-ab88-20f7382dd24c' // Default: Storage File Data SMB Share Contributor

// Get a reference to the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Assign role to the managed identity
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, roleDefinitionId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output roleAssignmentId string = roleAssignment.id
