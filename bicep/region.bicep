@description('The current region being deployed (e.g., "eu", "af")')
param currentRegion string

param location string = resourceGroup().location
param baseAppName string = 'nostria'
param defaultMediaCount int = 1

@description('Object defining the number of media servers per region. Example: {"eu": 2, "af": 1}')
param mediaCountPerRegion object = {}

@description('Object defining the app service plan SKUs per region. Example: {"eu": {"name": "B3", "tier": "Basic"}, "af": {"name": "B2", "tier": "Basic"}}')
param appServicePlanSkus object = {}

@description('Array of media server names')
param mediaNames array

@description('Key Vault name for retrieving secrets')
param keyVaultName string = ''

@description('Resource group where the Key Vault is located')
param globalResourceGroupName string = 'nostria-global'

@description('Whether to create Key Vault RBAC role assignments (disable if they already exist)')
param createKeyVaultRbacAssignments bool = false

// Read the media configuration file
var mediaConfigContent = loadTextContent('../config/media/config.yml')

module regionConfig 'modules/region-mapping.bicep' = {
  name: 'region-config-${currentRegion}'
  params: {
    regionCode: currentRegion
  }
}

var mediaCount = mediaCountPerRegion[?currentRegion] ?? defaultMediaCount

// Choose appropriate SKU based on region or default to B1 if region not specified
var selectedSku = appServicePlanSkus[?currentRegion] ?? {
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
      keyVaultName: keyVaultName
      globalResourceGroupName: globalResourceGroupName
      appSettings: [
        {
          name: 'BLOSSOM_CONFIG'
          value: '/app/data/config.yml'
        }
        {
          name: 'WEBSITES_PORT'
          value: '3000'
        }
        // Add Key Vault reference for admin password
        {
          name: 'BLOSSOM_ADMIN_PASSWORD'
          value: !empty(keyVaultName) ? '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=blossom-admin-password)' : ''
        }
      ]
    }
    dependsOn: [mediaStorageAccounts]
  }
]

// Grant Key Vault RBAC roles to media apps (cross-resource-group)
module mediaAppsKeyVaultRbac 'modules/cross-rg-key-vault-rbac.bicep' = [
  for i in range(0, mediaCount): if (!empty(keyVaultName) && createKeyVaultRbacAssignments) {
    name: '${baseAppName}-${currentRegion}-media-${toLower(mediaNames[i])}-kv-rbac'
    params: {
      principalId: mediaApps[i].outputs.webAppPrincipalId
      keyVaultName: keyVaultName
      keyVaultResourceGroupName: globalResourceGroupName
    }
    dependsOn: [mediaApps]
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
        value: 'https://ribo.${currentRegion}.nostria.app,https://rilo.${currentRegion}.nostria.app'
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

// Media URLs for the current region
output mediaAppUrls array = [
  for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}.${currentRegion}.nostria.app'
]

// Proxy Function App URL for the current region
output proxyFunctionAppUrl string = 'https://proxy.${currentRegion}.nostria.app'
