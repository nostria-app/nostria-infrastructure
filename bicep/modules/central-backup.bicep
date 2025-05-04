param name string = 'nostriabak'
param location string = resourceGroup().location
param sku string = 'Standard_LRS'

// Create a central backup storage account
resource backupStorageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  sku: {
    name: sku
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
  }
}

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: backupStorageAccount
  name: 'default'
}

// Create a file share for backups
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileServices
  name: 'backups'
  properties: {
    shareQuota: 5120 // 5TB - maximum size for a file share
    enabledProtocols: 'SMB'
  }
}

output id string = backupStorageAccount.id
output name string = backupStorageAccount.name
output fileShareName string = fileShare.name
