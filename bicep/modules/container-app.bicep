param name string
param location string = resourceGroup().location
param appServicePlanId string
param containerImage string
param customDomainName string = ''
param appSettings array = []
param storageAccountName string = ''

// Get a reference to the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountName)) {
  name: storageAccountName
}

// Get storage account key for initial mount but app will use managed identity later
var storageAccountKey = !empty(storageAccountName) ? storageAccount.listKeys().keys[0].value : ''

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
      alwaysOn: true
      appSettings: concat(appSettings, [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
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
      linuxFxVersion: 'DOCKER|${containerImage}'
      // Configure Azure Storage mount when storage account name is provided
      azureStorageAccounts: !empty(storageAccountName) ? {
        data: {
          type: 'AzureFiles'
          accountName: storageAccountName
          mountPath: '/home/data'
          shareName: 'data'
          accessKey: storageAccountKey // Required for initial mount, app will use managed identity later
        }
      } : {}
    }
  }
}

resource slotConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  parent: containerApp
  name: 'slotConfigNames'
  properties: {
    azureStorageConfigNames: ['data']
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
