// This module creates and configures SSL/TLS certificates for Azure Function Apps with custom domains
// It creates an App Service managed certificate and updates the hostname binding to enable SSL
param functionAppName string
param location string = resourceGroup().location
param customDomainName string
param appServicePlanId string

// Reference the Function App
resource functionApp 'Microsoft.Web/sites@2024-04-01' existing = {
  name: functionAppName
}

// Create App Service managed certificate for the Function App
resource functionAppCertificate 'Microsoft.Web/certificates@2024-04-01' = {
  name: '${functionAppName}-cert'
  location: location
  properties: {
    serverFarmId: appServicePlanId
    canonicalName: customDomainName
    hostNames: [customDomainName]
  }
  dependsOn: [
    functionApp
  ]
}

// Update the existing hostname binding to enable SSL with the managed certificate
resource sslBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  name: customDomainName
  parent: functionApp
  properties: {
    sslState: 'SniEnabled'
    thumbprint: functionAppCertificate.properties.thumbprint
    siteName: functionAppName
    hostNameType: 'Verified'
    azureResourceType: 'Website'
    customHostNameDnsRecordType: 'CName'
  }
}

output certificateThumbprint string = functionAppCertificate.properties.thumbprint
output certificateName string = functionAppCertificate.name
output sslEnabledUrl string = 'https://${customDomainName}'
