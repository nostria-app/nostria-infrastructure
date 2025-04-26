param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Parameters for configuring app instances
param relayCount int = 1
param mediaCount int = 1

// Server name arrays
var relayNames = [
  'Ribbo', 'Rilo', 'Riffu', 'Rixi', 'Rova', 'Rymba', 'Rorbo', 'Rukku', 'Razzle', 'Rilby',
  'Rambu', 'Rizzo', 'Rilka', 'Rulo', 'Ruvvi', 'Rinoo', 'Ribbly', 'Rasko', 'Roffo', 'Rilza',
  'Rmodo', 'Rembo', 'Rinzo', 'Ruppi', 'Rozi', 'Rucco', 'Rilma', 'Roppi', 'Ruvzo', 'Rilku',
  'Rirby', 'Riso', 'Ruzz', 'Roppo', 'Ruzi', 'Rilvo', 'Rordy', 'Ramzy', 'Rozzo', 'Rimp',
  'Rluno', 'Rippo', 'Rilno', 'Rikko', 'Rufko', 'Reppo', 'Romby', 'Rilzo', 'Rakku', 'Rumpo', 'Rifbo'
]

var mediaNames = [
  'Mibbo', 'Milo', 'Miffu', 'Mixi', 'Mova', 'Mymba', 'Morbo', 'Mukku', 'Mazzle', 'Milby',
  'Mambu', 'Mizzo', 'Milka', 'Mulo', 'Muvvi', 'Minoo', 'Mibbly', 'Masko', 'Moffo', 'Milza',
  'Mmodo', 'Membo', 'Minzo', 'Muppi', 'Mozi', 'Mucco', 'Milma', 'Moppi', 'Muvzo', 'Milku',
  'Mirby', 'Miso', 'Muzz', 'Moppo', 'Muzi', 'Milvo', 'Mordy', 'Mamzy', 'Mozzo', 'Mimp',
  'Mluno', 'Mippo', 'Milno', 'Mikko', 'Mufko', 'Meppo', 'Momby', 'Milzo', 'Makku', 'Mumpo', 'Mifbo'
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
    storageAccountKey: discoveryStorage.outputs.id.contains('Microsoft.Storage/storageAccounts') ? listKeys(discoveryStorage.outputs.id, '2022-05-01').keys[0].value : ''
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
    storageAccountKey: websiteStorage.outputs.id.contains('Microsoft.Storage/storageAccounts') ? listKeys(websiteStorage.outputs.id, '2022-05-01').keys[0].value : ''
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
    storageAccountKey: appStorage.outputs.id.contains('Microsoft.Storage/storageAccounts') ? listKeys(appStorage.outputs.id, '2022-05-01').keys[0].value : ''
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
      storageAccountKey: relayStorage[i].outputs.id.contains('Microsoft.Storage/storageAccounts') ? listKeys(relayStorage[i].outputs.id, '2022-05-01').keys[0].value : ''
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
      storageAccountKey: mediaStorage[i].outputs.id.contains('Microsoft.Storage/storageAccounts') ? listKeys(mediaStorage[i].outputs.id, '2022-05-01').keys[0].value : ''
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
