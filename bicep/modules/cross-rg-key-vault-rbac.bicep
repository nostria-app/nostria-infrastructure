// Cross-resource-group RBAC role assignment for Key Vault
@description('Principal ID that needs access')
param principalId string

@description('Key Vault name')
param keyVaultName string

@description('Key Vault resource group name')
param keyVaultResourceGroupName string

@description('Role definition ID for Key Vault Secrets User')
param roleDefinitionId string = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User

@description('Whether to create the role assignment (set to false if it already exists)')
param createRoleAssignment bool = true

// Deploy RBAC assignment in the Key Vault's resource group
module rbacAssignment 'key-vault-rbac-assignment.bicep' = {
  scope: resourceGroup(keyVaultResourceGroupName)
  name: 'kv-rbac-${uniqueString(principalId)}'
  params: {
    principalId: principalId
    keyVaultName: keyVaultName
    roleDefinitionId: roleDefinitionId
    createRoleAssignment: createRoleAssignment
  }
}

output success bool = rbacAssignment.outputs.success
