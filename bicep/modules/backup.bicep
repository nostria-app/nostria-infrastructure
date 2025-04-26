param sourceStorageAccountName string
param location string = resourceGroup().location
param backupStorageAccountSuffix string = 'bkp'
param sku string = 'Standard_LRS'

// Create a backup storage account
resource backupStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: '${sourceStorageAccountName}${backupStorageAccountSuffix}'
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

resource fileServices 'Microsoft.Storage/storageAccounts/fileServices@2024-01-01' = {
  parent: backupStorageAccount
  name: 'default'
}

// Create a backup share in the backup storage account
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2024-01-01' = {
  parent: fileServices
  name: 'backup'
  properties: {
    shareQuota: 5120 // 5TB - maximum size for a file share
    enabledProtocols: 'SMB'
  }
}

output id string = backupStorageAccount.id
output name string = backupStorageAccount.name
