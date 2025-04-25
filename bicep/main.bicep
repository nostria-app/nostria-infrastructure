param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Parameters for configuring app instances
param relayCount int = 1
param mediaCount int = 1

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
    containerImage: 'myrepo/discovery:latest'
    customDomainName: 'discovery.nostria.app'
    storageAccountName: discoveryStorage.outputs.name
    storageAccountKey: discoveryStorage.outputs.key
    appSettings: [
      {
        name: 'CUSTOM_SETTING'
        value: 'value'
      }
    ]
  }
}

// Deploy multiple relay instances as needed
module relayStorage 'modules/storage-account.bicep' = [for i in range(1, relayCount): {
  name: '${baseAppName}-relay${i}-storage-deployment'
  params: {
    name: '${baseAppName}relay${i}'
    location: location
  }
}]

module relayBackupStorage 'modules/backup.bicep' = [for i in range(1, relayCount): {
  name: '${baseAppName}-relay${i}-backup-deployment'
  params: {
    sourceStorageAccountName: relayStorage[i-1].outputs.name
    location: location
  }
}]

module relayApps 'modules/container-app.bicep' = [for i in range(1, relayCount): {
  name: '${baseAppName}-relay${i}-app-deployment'
  params: {
    name: 'relay${i}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'myrepo/relay:latest'
    customDomainName: 'relay${i}.nostria.app'
    storageAccountName: relayStorage[i-1].outputs.name
    storageAccountKey: relayStorage[i-1].outputs.key
  }
}]

// Deploy multiple media instances as needed
module mediaStorage 'modules/storage-account.bicep' = [for i in range(1, mediaCount): {
  name: '${baseAppName}-media${i}-storage-deployment'
  params: {
    name: '${baseAppName}media${i}'
    location: location
  }
}]

module mediaBackupStorage 'modules/backup.bicep' = [for i in range(1, mediaCount): {
  name: '${baseAppName}-media${i}-backup-deployment'
  params: {
    sourceStorageAccountName: mediaStorage[i-1].outputs.name
    location: location
  }
}]

module mediaApps 'modules/container-app.bicep' = [for i in range(1, mediaCount): {
  name: '${baseAppName}-media${i}-app-deployment'
  params: {
    name: 'media${i}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'myrepo/media:latest'
    customDomainName: 'media${i}.nostria.app'
    storageAccountName: mediaStorage[i-1].outputs.name
    storageAccountKey: mediaStorage[i-1].outputs.key
  }
}]

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name
output discoveryAppUrl string = 'https://${discoveryApp.outputs.hostname}'
output relayAppUrls array = [for i in range(1, relayCount): 'https://relay${i}.nostria.app']
output mediaAppUrls array = [for i in range(1, mediaCount): 'https://media${i}.nostria.app']