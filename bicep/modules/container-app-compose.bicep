// filepath: c:\src\github\nostria\nostria-infrastructure\bicep\modules\container-app-compose.bicep
param name string
param location string = resourceGroup().location
param appServicePlanId string
param customDomainName string = ''
param appSettings array = []
param dockerComposeYaml string
param storageAccountName string = ''

// Get a reference to the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountName)) {
  name: storageAccountName
}

// Get storage account key for initial mount but app will use managed identity later
var storageAccountKey = !empty(storageAccountName) ? storageAccount.listKeys().keys[0].value : ''

// Replace placeholder in docker-compose.yml with actual region value
// var processedDockerComposeYaml = !empty(dockerComposeYaml) ? replace(dockerComposeYaml, '${currentRegion}', appSettings[?(@.name == 'Media__Region')].value) : dockerComposeYaml

// Main container app resource with docker-compose support
resource containerApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      http20Enabled: true
      alwaysOn: true
      appSettings: concat(appSettings, [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://ghcr.io'
        }
        {
          name: 'DOCKER_ENABLE_CI'
          value: 'true'
        }
      ], !empty(storageAccountName) ? [
        {
          name: 'WEBSITES_CONTAINER_START_TIME_LIMIT'
          value: '600'  // Increase container start time limit to allow mount to complete
        }
        {
          name: 'CUSTOM_MOUNT_PATH'
          value: '/data'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT'  // Standard Azure env variable name
          value: storageAccountName
        }
        {
          name: 'WEBSITES_MOUNT_ENABLED'
          value: '1'  // Ensure storage mounting is explicitly enabled
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
      ] : [])
      linuxFxVersion: 'COMPOSE|${base64(dockerComposeYaml)}'
      // Configure Azure Storage mount when storage account name is provided
      azureStorageAccounts: !empty(storageAccountName) ? {
        media: {
          type: 'AzureFiles'
          accountName: storageAccountName
          mountPath: '/data'
          shareName: 'data'
          accessKey: storageAccountKey // Required for initial mount, app will use managed identity later
        }
      } : {}
    }
  }
}

// Additional configuration for storage access
// resource siteConfig 'Microsoft.Web/sites/config@2024-04-01' = if (!empty(storageAccountName)) {
//   parent: containerApp
//   name: 'web'
//   properties: {
//     ftpsState: 'Disabled'
//     scmIpSecurityRestrictions: []
//   }
// }

// Hostname binding for custom domain
resource hostnameBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (!empty(customDomainName)) {
  parent: containerApp
  name: customDomainName
  properties: {
    hostNameType: 'Verified'
    sslState: 'Disabled'
    thumbprint: ''
    siteName: name
    azureResourceType: 'Website'
    customHostNameDnsRecordType: 'CName'
  }
}

output id string = containerApp.id
output name string = containerApp.name
output hostname string = containerApp.properties.defaultHostName
output webAppPrincipalId string = containerApp.identity.principalId
output hostnameBindingResourceId string = !empty(customDomainName) ? hostnameBinding.id : ''
