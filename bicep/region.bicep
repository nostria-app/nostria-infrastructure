@description('The current region being deployed (e.g., "eu", "af")')
param currentRegion string

param location string = resourceGroup().location
param baseAppName string = 'nostria'
param defaultRelayCount int = 1
param defaultMediaCount int = 1
@description('Array of region codes where to deploy resources (e.g., ["eu", "af"])')
param deployRegions array = ['eu', 'af']
@description('Object defining the number of relay servers per region. Example: {"eu": 2, "af": 1}')
param relayCountPerRegion object = {}
@description('Object defining the number of media servers per region. Example: {"eu": 2, "af": 1}')
param mediaCountPerRegion object = {}

@description('Array of relay server names')
param relayNames array
@description('Array of media server names')
param mediaNames array

var isPrimaryRegion = currentRegion == 'eu'

module regionConfig 'modules/region-mapping.bicep' = {
  name: 'region-config-${currentRegion}'
  params: {
    regionCode: currentRegion
  }
}

var relayCount = contains(relayCountPerRegion, currentRegion) ? relayCountPerRegion[currentRegion] : defaultRelayCount
var mediaCount = contains(mediaCountPerRegion, currentRegion) ? mediaCountPerRegion[currentRegion] : defaultMediaCount

// Deploy App Service Plan for the current region
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: '${baseAppName}-plan-${currentRegion}-deployment'
  params: {
    name: '${baseAppName}-plan-${currentRegion}'
    location: location
  }
}

// Deploy Discovery App for the current region
module discoveryApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-discovery-app-${currentRegion}-deployment'
  params: {
    name: 'nostria-discovery-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'discovery-${currentRegion}.nostria.app'
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
        name: 'Lmdb__DatabasePath'
        value: '/home/data'
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
      {
        name: 'Relay__Region'
        value: currentRegion
      }
    ]
  }
}

// Certificate for Discovery App
module discoveryAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-discovery-app-${currentRegion}-cert-deployment'
  params: {
    name: 'nostria-discovery-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'discovery-${currentRegion}.nostria.app'
    containerAppId: discoveryApp.outputs.id
  }
  dependsOn: [discoveryApp]
}

// Deploy Relay Apps for the current region
module relayStorageAccounts 'modules/storage-account.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-${currentRegion}-storage-deployment'
  params: {
    name: '${toLower(replace(relayNames[i], '-', ''))}${currentRegion}sa'
    location: location
  }
}]

module relayApps 'modules/container-app.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-${currentRegion}-deployment'
  params: {
    name: 'nostria-${toLower(relayNames[i])}-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-relay:latest'
    customDomainName: '${toLower(relayNames[i])}-${currentRegion}.nostria.app'
    storageAccountName: relayStorageAccounts[i].outputs.name
    appSettings: [
      {
        name: 'Relay__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Relay__PostingPolicy'
        value: 'https://relay.nostria.com/posting-policy'
      }
      {
        name: 'Relay__PrivacyPolicy'
        value: 'https://relay.nostria.com/privacy-policy'
      }
      {
        name: 'Relay__Region'
        value: currentRegion
      }
      {
        name: 'Lmdb__DatabasePath'
        value: '/data'
      }
      {
        name: 'Lmdb__MaxReaders'
        value: 4096
      }
      {
        name: 'Lmdb__SizeInMb'
        value: 1024
      }
    ]
  }
  dependsOn: [relayStorageAccounts]
}]

// Assign Storage File Data SMB Share Contributor role to relay apps
module relayStorageRoleAssignments 'modules/role-assignment.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-${currentRegion}-role-assignment'
  params: {
    storageAccountName: relayStorageAccounts[i].outputs.name
    principalId: relayApps[i].outputs.webAppPrincipalId
  }
  dependsOn: [relayApps, relayStorageAccounts]
}]

// Certificates for Relay Apps
module relayAppsCerts 'modules/container-app-certificate.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-${currentRegion}-cert-deployment'
  params: {
    name: 'nostria-${toLower(relayNames[i])}-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(relayNames[i])}-${currentRegion}.nostria.app'
    containerAppId: relayApps[i].outputs.id
  }
  dependsOn: [relayApps]
}]

// Media Apps (Multiple instances based on mediaCount) using docker-compose
module mediaStorageAccounts 'modules/storage-account.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-${currentRegion}-storage-deployment'
  params: {
    name: '${toLower(replace(mediaNames[i], '-', ''))}${currentRegion}sa'
    location: location
  }
}]

module mediaApps 'modules/container-app-compose.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-${currentRegion}-deployment'
  params: {
    name: 'nostria-${toLower(mediaNames[i])}-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(mediaNames[i])}-${currentRegion}.nostria.app'
    storageAccountName: mediaStorageAccounts[i].outputs.name
    dockerComposeYaml: '''
version: '3'
services:
  media-app:
    image: ghcr.io/nostria-app/nostria-media:latest
    restart: always
    ports:
      - "3000:3000"
    environment:
      - Media__StoragePath=/data
      - Media__Contact=17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515
      - Media__PrivacyPolicy=https://media.nostria.com/privacy-policy
  media-processor:
    image: ghcr.io/nostria-app/nostria-media-processor:latest
    restart: always
    depends_on:
      - media-app
'''
    appSettings: [
      {
        name: 'WEBSITES_PORT'
        value: '3000'
      }
      {
        name: 'Media__StoragePath'
        value: '/data'
      }
      {
        name: 'Media__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Media__PrivacyPolicy'
        value: 'https://media.nostria.com/privacy-policy'
      }
      {
        name: 'Media__Region'
        value: currentRegion
      }
    ]
  }
  dependsOn: [mediaStorageAccounts]
}]

// Assign Storage File Data SMB Share Contributor role to media apps
module mediaStorageRoleAssignments 'modules/role-assignment.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-${currentRegion}-role-assignment'
  params: {
    storageAccountName: mediaStorageAccounts[i].outputs.name
    principalId: mediaApps[i].outputs.webAppPrincipalId
  }
  dependsOn: [mediaApps, mediaStorageAccounts]
}]

// Certificates for Media Apps
module mediaAppsCerts 'modules/container-app-certificate.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-${currentRegion}-cert-deployment'
  params: {
    name: 'nostria-${toLower(mediaNames[i])}-${currentRegion}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(mediaNames[i])}-${currentRegion}.nostria.app'
    containerAppId: mediaApps[i].outputs.id
  }
  dependsOn: [mediaApps]
}]

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name

// Discovery app URL for the current region
output discoveryAppUrl string = 'https://discovery-${currentRegion}.nostria.app'

// Relay URLs for the current region
output relayAppUrls array = [for i in range(0, relayCount): 'https://${toLower(relayNames[i])}-${currentRegion}.nostria.app']

// Media URLs for the current region
output mediaAppUrls array = [for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}-${currentRegion}.nostria.app']
