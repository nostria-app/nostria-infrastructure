param name string
param location string = resourceGroup().location
param appServicePlanId string
param containerImage string
param customDomainName string = ''
param appSettings array = []
param storageAccountName string

// Main container app resource
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
      appSettings: concat(appSettings, [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
        {
          name: 'AZURE_STORAGE_AUTHENTICATION_TYPE'
          value: 'ManagedIdentity'
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
      ])
      linuxFxVersion: 'DOCKER|${containerImage}'
      // Storage mount is commented out but can be enabled if needed
      // azureStorageAccounts: {
      //   data: {
      //     type: 'AzureFiles'
      //     accountName: storageAccountName
      //     mountPath: '/data'
      //     shareName: 'data'
      //     accessKey: '' // No access key - we use managed identity instead
      //   }
      // }
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
