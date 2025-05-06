// filepath: c:\src\github\nostria\nostria-infrastructure\bicep\modules\container-app-compose.bicep
param name string
param location string = resourceGroup().location
param appServicePlanId string
param customDomainName string = ''
param appSettings array = []
param dockerComposeYaml string
param storageAccountName string = ''

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
        // Default port is now commented out as it should be specified in the appSettings parameter
        // {
        //   name: 'WEBSITES_PORT'
        //   value: '8080'
        // }
      ], !empty(storageAccountName) ? [
        {
          name: 'AZURE_STORAGE_AUTHENTICATION_TYPE'
          value: 'ManagedIdentity'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
      ] : [])
      linuxFxVersion: 'COMPOSE|${base64(dockerComposeYaml)}'
    }
  }
}

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
