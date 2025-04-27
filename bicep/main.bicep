param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Parameters for configuring app instances
param relayCount int = 1
param mediaCount int = 1

// Server name arrays
var relayNames = [
  'Ribo', 'Rilo', 'Rifu', 'Rixi', 'Rova', 'Ryma', 'Robo', 'Ruku', 'Raze', 'Ruby'
  'Ramu', 'Rizo', 'Rika', 'Rulo', 'Ruvi', 'Rino', 'Riby', 'Rask', 'Rofo', 'Rilz'
  'Rudo', 'Remo', 'Rinz', 'Rupi', 'Rozi', 'Ruco', 'Rima', 'Ropi', 'Ruzo', 'Riku'
  'Riry', 'Riso', 'Ruzz', 'Ropo', 'Ruzi', 'Rilv', 'Rork', 'Ramy', 'Rozo', 'Rimp'
  'Runo', 'Ripp', 'Rino', 'Riko', 'Rufo', 'Repo', 'Romy', 'Rilz', 'Raku', 'Rumo'
]

var mediaNames = [
  'Mibo', 'Milo', 'Mifu', 'Mixi', 'Mova', 'Myma', 'Mobo', 'Muku', 'Maze', 'Miby'
  'Mamu', 'Mizo', 'Mika', 'Mulo', 'Muvi', 'Mino', 'Miby', 'Mask', 'Mofo', 'Milz'
  'Mudo', 'Memo', 'Minz', 'Mupi', 'Mozi', 'Muco', 'Mima', 'Mopi', 'Muzo', 'Miku'
  'Miry', 'Miso', 'Muzz', 'Mopo', 'Muzi', 'Milv', 'Mork', 'Mamy', 'Mozo', 'Mimp'
  'Muno', 'Mipp', 'Mino', 'Miko', 'Mufo', 'Mepo', 'Momy', 'Milz', 'Maku', 'Mumo'
]

// Deploy the main App Service Plan for all container apps
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: '${baseAppName}-plan-deployment'
  params: {
    name: '${baseAppName}-linux-plan'
    location: location
  }
}

// Storage Account for Discovery
module discoveryStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-discovery-storage-deployment'
  params: {
    name: '${baseAppName}discovery'
    location: location
  }
}

resource discoveryStorageInstance 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: '${baseAppName}discovery'
}

// Backup Storage for Discovery
module discoveryBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-discovery-backup-deployment'
  params: {
    sourceStorageAccountName: discoveryStorage.outputs.name
    location: location
  }
}

// Discovery App (Single instance)
module discoveryApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-discovery-app-deployment'
  params: {
    name: 'discovery'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'discovery.nostria.app'
    storageAccountName: discoveryStorage.outputs.name
    storageAccountKey: discoveryStorageInstance.listKeys().keys[0].value
    appSettings: [
      {
        name: 'CUSTOM_SETTING'
        value: 'value'
      }
      {
        name: 'Lmdb__MaxReaders'
        value: 4096
      }
      {
        name: 'Lmdb__SizeInMb'
        value: 1024
      }
      {
        name: 'Relay__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Relay__PostingPolicy'
        value: 'https://discovery.nostria.com/posting-policy'
      }
      {
        name: 'Relay__PrivacyPolicy'
        value: 'https://discovery.nostria.com/privacy-policy'
      }
    ]
  }
}

// Storage Account for Website
module websiteStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-website-storage-deployment'
  params: {
    name: '${baseAppName}website'
    location: location
  }
}

resource websiteStorageInstance 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: '${baseAppName}website'
  // scope: resourceGroup(subscriptionId, kvResourceGroup )
}

// Backup Storage for Website
module websiteBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-website-backup-deployment'
  params: {
    sourceStorageAccountName: websiteStorage.outputs.name
    location: location
  }
}

// Website App (Single instance)
module websiteApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-website-app-deployment'
  params: {
    name: 'website'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'www.nostria.app'
    storageAccountName: websiteStorage.outputs.name
    storageAccountKey: websiteStorageInstance.listKeys().keys[0].value
    appSettings: []
  }
}

// Storage Account for Main app site
module appStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-app-storage-deployment'
  params: {
    name: '${baseAppName}app'
    location: location
  }
}

resource appStorageInstance 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: '${baseAppName}app'
  // scope: resourceGroup(subscriptionId, kvResourceGroup )
}

// Backup Storage for Main app site
module appBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-app-backup-deployment'
  params: {
    sourceStorageAccountName: appStorage.outputs.name
    location: location
  }
}

// Main App (Single instance)
module mainApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-main-app-deployment'
  params: {
    name: 'app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'nostria.app'
    storageAccountName: appStorage.outputs.name
    storageAccountKey: appStorageInstance.listKeys().keys[0].value
    appSettings: []
  }
}

// Deploy multiple relay instances as needed
module relayStorage 'modules/storage-account.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${toLower(relayNames[i])}-storage-deployment'
    params: {
      name: '${baseAppName}${toLower(relayNames[i])}'
      location: location
    }
  }
]

resource relayStorageInstance 'Microsoft.Storage/storageAccounts@2023-01-01' existing = [
  for i in range(0, relayCount): {
    name: '${baseAppName}${toLower(relayNames[i])}'
  }
]

module relayBackupStorage 'modules/backup.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${toLower(relayNames[i])}-backup-deployment'
    params: {
      sourceStorageAccountName: relayStorage[i].outputs.name
      location: location
    }
  }
]

module relayApps 'modules/container-app.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${toLower(relayNames[i])}-app-deployment'
    params: {
      name: toLower(relayNames[i])
      location: location
      appServicePlanId: appServicePlan.outputs.id
      containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
      customDomainName: '${toLower(relayNames[i])}.nostria.app'
      storageAccountName: relayStorage[i].outputs.name
      storageAccountKey: relayStorageInstance[i].listKeys().keys[0].value
    }
  }
]

// Deploy multiple media instances as needed
module mediaStorage 'modules/storage-account.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${toLower(mediaNames[i])}-storage-deployment'
    params: {
      name: '${baseAppName}${toLower(mediaNames[i])}'
      location: location
    }
  }
]

resource mediaStorageInstance 'Microsoft.Storage/storageAccounts@2023-01-01' existing = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}${toLower(mediaNames[i])}'
  }
]

module mediaBackupStorage 'modules/backup.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${toLower(mediaNames[i])}-backup-deployment'
    params: {
      sourceStorageAccountName: mediaStorage[i].outputs.name
      location: location
    }
  }
]

module mediaApps 'modules/container-app.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${toLower(mediaNames[i])}-app-deployment'
    params: {
      name: toLower(mediaNames[i])
      location: location
      appServicePlanId: appServicePlan.outputs.id
      containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
      customDomainName: '${toLower(mediaNames[i])}.nostria.app'
      storageAccountName: mediaStorage[i].outputs.name
      storageAccountKey: mediaStorageInstance[i].listKeys().keys[0].value
    }
  }
]

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name
output discoveryAppUrl string = 'https://${discoveryApp.outputs.hostname}'
output websiteAppUrl string = 'https://${websiteApp.outputs.hostname}'
output mainAppUrl string = 'https://${mainApp.outputs.hostname}'
output relayAppUrls array = [for i in range(0, relayCount): 'https://${toLower(relayNames[i])}.nostria.app']
output mediaAppUrls array = [for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}.nostria.app']
