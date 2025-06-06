param name string
param location string = resourceGroup().location
param customDomainName string
param appServicePlanId string

// Create App Service managed certificate if custom domain is provided
resource appServiceCertificate 'Microsoft.Web/certificates@2024-04-01' = {
  name: '${name}-cert'
  location: location
  properties: {
    serverFarmId: appServicePlanId
    canonicalName: customDomainName
    hostNames: [customDomainName]
  }
}

// resource appServiceLegacyCertificate 'Microsoft.Web/certificates@2024-04-01' = {
//   name: '${name}-legacy-cert'
//   location: location
//   properties: {
//     serverFarmId: appServicePlanId
//     canonicalName: legacyDomainName
//     hostNames: [legacyDomainName]
//   }
// }

// Reference the parent App Service site
resource appServiceSite 'Microsoft.Web/sites@2024-04-01' existing = {
  name: name
}

// Update hostname binding to enable SSL with the managed certificate
resource sslBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
  name: customDomainName
  parent: appServiceSite
  properties: {
    sslState: 'SniEnabled'
    thumbprint: appServiceCertificate.properties.thumbprint
    siteName: name
    hostNameType: 'Verified'
    azureResourceType: 'Website'
    customHostNameDnsRecordType: 'CName'
  }
}

// resource sslBindingLegacy 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = {
//   name: legacyDomainName
//   parent: appServiceSite
//   properties: {
//     sslState: 'SniEnabled'
//     thumbprint: appServiceLegacyCertificate.properties.thumbprint
//     siteName: name
//     hostNameType: 'Verified'
//     azureResourceType: 'Website'
//     customHostNameDnsRecordType: 'CName'
//   }
//   dependsOn: [
//     sslBinding
//   ]
// }

output certificateThumbprint string = appServiceCertificate.properties.thumbprint
// output legacyCertificateThumbprint string = appServiceLegacyCertificate.properties.thumbprint
