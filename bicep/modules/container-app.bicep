param name string
param location string = resourceGroup().location
param appServicePlanId string
param containerImage string
param customDomainName string = ''
param appSettings array = []
param storageAccountName string
param storageAccountKey string
param mountPath string = '/data'
param shareName string = 'data'

resource containerApp 'Microsoft.Web/sites@2022-03-01' = {
  name: name
  location: location
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      appSettings: concat(appSettings, [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'true'
        }
      ])
      linuxFxVersion: 'DOCKER|${containerImage}'
      azureStorageAccounts: {
        data: {
          type: 'AzureFiles'
          accountName: storageAccountName
          accessKey: storageAccountKey
          mountPath: mountPath
          shareName: shareName
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