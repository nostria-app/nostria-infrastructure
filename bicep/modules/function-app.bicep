param name string
param location string = resourceGroup().location
param appServicePlanId string
param customDomainName string = ''
param appSettings array = []
param storageAccountName string

// Get a reference to the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: storageAccountName
}

// Main Function App resource
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    reserved: true
    siteConfig: {
      linuxFxVersion: 'Node|22'
      appSettings: concat(
        appSettings,
        [
          {
            name: 'AzureWebJobsStorage'
            value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
          }
          {
            name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
            value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
          }
          {
            name: 'WEBSITE_CONTENTSHARE'
            value: toLower(name)
          }
          {
            name: 'FUNCTIONS_EXTENSION_VERSION'
            value: '~4'
          }
          {
            name: 'WEBSITE_NODE_DEFAULT_VERSION'
            value: '~22'
          }
          {
            name: 'FUNCTIONS_WORKER_RUNTIME'
            value: 'node'
          }
          {
            name: 'AZURE_STORAGE_ACCOUNT'
            value: storageAccountName
          }
          {
            name: 'AZURE_STORAGE_AUTHENTICATION_TYPE'
            value: 'ManagedIdentity'
          }
        ]
      )
      cors: {
        allowedOrigins: ['*']
        supportCredentials: false
      }
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
}

// Hostname binding for custom domain
resource hostnameBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (!empty(customDomainName)) {
  parent: functionApp
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

output id string = functionApp.id
output name string = functionApp.name
output hostname string = functionApp.properties.defaultHostName
output functionAppPrincipalId string = functionApp.identity.principalId
