@description('The current region being deployed (e.g., "eu", "af")')
param currentRegion string

param location string = resourceGroup().location
param baseAppName string = 'nostria'
param defaultRelayCount int = 1
param defaultMediaCount int = 1

@description('Object defining the number of relay servers per region. Example: {"eu": 2, "af": 1}')
param relayCountPerRegion object = {}
@description('Object defining the number of media servers per region. Example: {"eu": 2, "af": 1}')
param mediaCountPerRegion object = {}

@description('Object defining the app service plan SKUs per region. Example: {"eu": {"name": "B3", "tier": "Basic"}, "af": {"name": "B2", "tier": "Basic"}}')
param appServicePlanSkus object = {}

@description('Array of relay server names')
param relayNames array
@description('Array of media server names')
param mediaNames array

// Read the relay configuration file
var strfryConfigContent = loadTextContent('../config/relay/strfry.conf')
var mediaConfigContent = loadTextContent('../config/media/config.yml')

module regionConfig 'modules/region-mapping.bicep' = {
  name: 'region-config-${currentRegion}'
  params: {
    regionCode: currentRegion
  }
}

var relayCount = contains(relayCountPerRegion, currentRegion) ? relayCountPerRegion[currentRegion] : defaultRelayCount
var mediaCount = contains(mediaCountPerRegion, currentRegion) ? mediaCountPerRegion[currentRegion] : defaultMediaCount

// Choose appropriate SKU based on region or default to B1 if region not specified
var selectedSku = contains(appServicePlanSkus, currentRegion) ? appServicePlanSkus[currentRegion] : {
  name: 'B1'
  tier: 'Basic'
}

// Deploy App Service Plan for the current region
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: '${baseAppName}-${currentRegion}-plan-deployment'
  params: {
    name: '${baseAppName}-${currentRegion}-plan'
    location: location
    sku: selectedSku
  }
}



// Deploy Relay Apps for the current region
module relayStorageAccounts 'modules/storage-account.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${currentRegion}-relay-${toLower(relayNames[i])}-storage-deployment'
    params: {
      name: '${toLower(replace(relayNames[i], '-', ''))}${currentRegion}st'
      location: location
    }
  }
]

module relayApps 'modules/container-app.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${currentRegion}-relay-${toLower(relayNames[i])}-deployment'
    params: {
      name: 'nostria-${currentRegion}-${toLower(relayNames[i])}'
      location: location
      appServicePlanId: appServicePlan.outputs.id
      // containerImage: 'ghcr.io/nostria-app/nostria-relay:latest'
      containerImage: 'ghcr.io/hoytech/strfry:latest'
      customDomainName: '${toLower(relayNames[i])}.${currentRegion}.nostria.app'
      storageAccountName: relayStorageAccounts[i].outputs.name
      appSettings: [
        {
          name: 'STRFRY_CONFIG'
          value: '/app/data/strfry.conf'
        }
      ]
      // startupCommand: relayStartupCommand
      configContent: strfryConfigContent
      configFileName: 'strfry.conf'
      startupCommand: 'relay --config=/app/data/strfry.conf'
      // startupCommand: '--config=/app/data/strfry.conf'
    }
    dependsOn: [relayStorageAccounts]
  }
]

// Assign Storage File Data SMB Share Contributor role to relay apps
module relayStorageRoleAssignments 'modules/role-assignment.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${currentRegion}-relay-${toLower(relayNames[i])}-role-assignment'
    params: {
      storageAccountName: relayStorageAccounts[i].outputs.name
      principalId: relayApps[i].outputs.webAppPrincipalId
    }
    dependsOn: [relayApps, relayStorageAccounts]
  }
]

// Certificates for Relay Apps
module relayAppsCerts 'modules/container-app-certificate.bicep' = [
  for i in range(0, relayCount): {
    name: '${baseAppName}-${currentRegion}-relay-${toLower(relayNames[i])}-cert-deployment'
    params: {
      name: 'nostria-${currentRegion}-${toLower(relayNames[i])}'
      location: location
      appServicePlanId: appServicePlan.outputs.id
      customDomainName: '${toLower(relayNames[i])}.${currentRegion}.nostria.app'
    }
    dependsOn: [relayApps]
  }
]

// Media Apps (Multiple instances based on mediaCount) using docker-compose
module mediaStorageAccounts 'modules/storage-account.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${currentRegion}-media-${toLower(mediaNames[i])}-storage-deployment'
    params: {
      name: '${toLower(replace(mediaNames[i], '-', ''))}${currentRegion}st'
      location: location
    }
  }
]

module mediaApps 'modules/container-app.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${currentRegion}-media-${toLower(mediaNames[i])}-deployment'
    params: {
      name: 'nostria-${currentRegion}-${toLower(mediaNames[i])}'
      location: location
      appServicePlanId: appServicePlan.outputs.id
      containerImage: 'ghcr.io/nostria-app/nostria-media:latest'
      customDomainName: '${toLower(mediaNames[i])}.${currentRegion}.nostria.app'
      storageAccountName: mediaStorageAccounts[i].outputs.name
      configContent: mediaConfigContent
      configFileName: 'config.yml'
      appSettings: [
        {
          name: 'BLOSSOM_CONFIG'
          value: '/app/data/config.yml'
        }
        {
          name: 'WEBSITES_PORT'
          value: '3000'
        }
      ]
    }
    dependsOn: [mediaStorageAccounts]
  }
]

// Assign Storage File Data SMB Share Contributor role to media apps
module mediaStorageRoleAssignments 'modules/role-assignment.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${currentRegion}-media-${toLower(mediaNames[i])}-role-assignment'
    params: {
      storageAccountName: mediaStorageAccounts[i].outputs.name
      principalId: mediaApps[i].outputs.webAppPrincipalId
    }
    dependsOn: [mediaApps, mediaStorageAccounts]
  }
]

// Certificates for Media Apps
module mediaAppsCerts 'modules/container-app-certificate.bicep' = [
  for i in range(0, mediaCount): {
    name: '${baseAppName}-${currentRegion}-media-${toLower(mediaNames[i])}-cert-deployment'
    params: {
      name: 'nostria-${currentRegion}-${toLower(mediaNames[i])}'
      location: location
      appServicePlanId: appServicePlan.outputs.id
      customDomainName: '${toLower(mediaNames[i])}.${currentRegion}.nostria.app'
    }
    dependsOn: [mediaApps]
  }
]

// Create array of relay endpoints for proxy configuration
var relayEndpoints = [for i in range(0, relayCount): 'https://${toLower(relayNames[i])}.${currentRegion}.nostria.app']

// Deploy Storage Account for Proxy Function App
module proxyStorageAccount 'modules/storage-account.bicep' = {
  name: '${baseAppName}-${currentRegion}-proxy-storage-deployment'
  params: {
    name: 'proxy${currentRegion}st'
    location: location
  }
}

// Deploy Nostria Proxy Function App for the current region
module proxyFunctionApp 'modules/function-app.bicep' = {
  name: '${baseAppName}-${currentRegion}-proxy-function-deployment'
  params: {
    name: 'nostria-${currentRegion}-proxy'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'proxy.${currentRegion}.nostria.app'
    storageAccountName: proxyStorageAccount.outputs.name
    appSettings: [
      {
        name: 'RELAY_REGION'
        value: currentRegion
      }
      {
        name: 'RELAY_ENDPOINTS'
        value: join(relayEndpoints, ',')
      }
    ]
  }
}

// Assign Storage Blob Data Contributor role to proxy function app
module proxyStorageRoleAssignment 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-${currentRegion}-proxy-role-assignment'
  params: {
    storageAccountName: proxyStorageAccount.outputs.name
    principalId: proxyFunctionApp.outputs.functionAppPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  }
}

// Certificate for Proxy Function App
module proxyFunctionAppCert 'modules/function-app-certificate.bicep' = {
  name: '${baseAppName}-${currentRegion}-proxy-function-cert-deployment'
  params: {
    functionAppName: 'nostria-${currentRegion}-proxy'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'proxy.${currentRegion}.nostria.app'
  }
  dependsOn: [
    proxyFunctionApp
  ]
}

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name

// Relay URLs for the current region
output relayAppUrls array = [
  for i in range(0, relayCount): 'https://${toLower(relayNames[i])}.${currentRegion}.nostria.app'
]

// Media URLs for the current region
output mediaAppUrls array = [
  for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}.${currentRegion}.nostria.app'
]

// Proxy Function App URL for the current region
output proxyFunctionAppUrl string = 'https://proxy.${currentRegion}.nostria.app'
