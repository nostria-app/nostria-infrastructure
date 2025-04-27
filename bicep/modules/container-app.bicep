param name string
param location string = resourceGroup().location
param appServicePlanId string
param containerImage string
param customDomainName string = ''
param appSettings array = []
param storageAccountName string
param mountPath string = '/data'
param shareName string = 'data'

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
      azureStorageAccounts: {
        data: {
          type: 'AzureFiles'
          accountName: storageAccountName
          mountPath: mountPath
          shareName: shareName
          accessKey: '' // No access key - we use managed identity instead
        }
      }
    }
  }
  
  // Add custom hostname binding if provided
  resource hostnameBinding 'hostNameBindings' = if (!empty(customDomainName)) {
    name: customDomainName
    properties: {
      siteName: name
      hostNameType: 'Verified'
    }
  }
}

output id string = containerApp.id
output name string = containerApp.name
output hostname string = containerApp.properties.defaultHostName
output webAppPrincipalId string = containerApp.identity.principalId
