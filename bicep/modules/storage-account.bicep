param name string
param location string = resourceGroup().location
param sku string = 'Standard_LRS'
param kind string = 'StorageV2'

@description('Principal ID of the web app managed identity that needs access to the storage')
param webAppPrincipalId string = ''

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  kind: kind
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// Create a default share for the storage account
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: 'data'
  properties: {
    shareQuota: 5120 // 5TB - maximum size for a file share
    enabledProtocols: 'SMB'
  }
}

// Assign Storage File Data SMB Share Contributor role to the web app's managed identity if provided
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(webAppPrincipalId)) {
  name: guid(storageAccount.id, webAppPrincipalId, 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Storage File Data SMB Share Contributor role ID
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: webAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
output apiVersion string = storageAccount.apiVersion

// Outputs
// output storageAccountId string = storageAccount.id
// output storageAccountName string = storageAccount.name
// output fileShareName string = fileShareName
// output fileShareResourceId string = fileShare.id
