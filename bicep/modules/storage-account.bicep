param name string
param location string = resourceGroup().location
param sku string = 'Standard_LRS'
param kind string = 'StorageV2'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
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

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2022-05-01' = {
  parent: storageAccount
  name: 'default'
}

// Create a default share for the storage account
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-05-01' = {
  parent: fileServices
  name: 'data'
  properties: {
    shareQuota: 5120 // 5TB - maximum size for a file share
    enabledProtocols: 'SMB'
  }
}

output id string = storageAccount.id
output name string = storageAccount.name
@secure()
output key string = storageAccount.listKeys().keys[0].value
