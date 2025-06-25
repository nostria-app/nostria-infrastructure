// Cosmos DB native RBAC role assignment module
param cosmosDbAccountName string
param principalId string
@description('Use built-in Cosmos DB Data Contributor role')
param useBuiltInDataContributorRole bool = true

// Get a reference to the Cosmos DB account
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosDbAccountName
}

// Create a custom role definition for Cosmos DB data operations if not using built-in
resource customRoleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-11-15' = if (!useBuiltInDataContributorRole) {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, 'custom-data-contributor')
  properties: {
    roleName: 'Custom Data Contributor'
    type: 'CustomRole'
    assignableScopes: [
      cosmosAccount.id
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
        ]
        notDataActions: []
      }
    ]
  }
}

// Assign the role to the managed identity using Cosmos DB native RBAC
resource roleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, principalId, 'sql-role-assignment')
  properties: {
    principalId: principalId
    roleDefinitionId: useBuiltInDataContributorRole 
      ? '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002' // Built-in Cosmos DB Data Contributor
      : customRoleDefinition.id
    scope: cosmosAccount.id
  }
}

output roleAssignmentId string = roleAssignment.id
output roleDefinitionId string = useBuiltInDataContributorRole 
  ? '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
  : customRoleDefinition.id
