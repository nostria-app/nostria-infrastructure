param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Deploy App Service Plan for the current region
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: '${baseAppName}-plan-deployment'
  params: {
    name: '${baseAppName}-plan'
    location: location
  }
}

// Deploy a centralized backup storage account - ONLY IN PRIMARY REGION
module centralBackupStorage 'modules/central-backup.bicep' = {
  name: '${baseAppName}-central-backup-deployment'
  params: {
    name: 'nostriabak'
    location: location
  }
}

// Website App (Single instance)
module websiteApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-website-app-deployment'
  params: {
    name: 'nostria-website'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-website:latest'
    customDomainName: 'www.nostria.app'
    appSettings: []
  }
}

// Certificate for Website App
module websiteAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-website-app-cert-deployment'
  params: {
    name: 'nostria-website'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'www.nostria.app'
    containerAppId: websiteApp.outputs.id
  }
  dependsOn: [websiteApp]
}

// Main App (Single instance)
module mainApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-main-app-deployment'
  params: {
    name: 'nostria-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria:latest'
    customDomainName: 'nostria.app'
    appSettings: []
  }
}

// Certificate for Main App
module mainAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-main-app-cert-deployment'
  params: {
    name: 'nostria-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'nostria.app'
    containerAppId: mainApp.outputs.id
  }
  dependsOn: [mainApp]
}

// Metadata App (Single instance)
module metadataApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-metadata-app-deployment'
  params: {
    name: 'nostria-metadata'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-metadata:latest'
    customDomainName: 'metadata.nostria.app'
    appSettings: []
  }
}

// Certificate for Metadata App
module metadataAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-metadata-app-cert-deployment'
  params: {
    name: 'nostria-metadata'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'metadata.nostria.app'
    containerAppId: metadataApp.outputs.id
  }
  dependsOn: [metadataApp]
}

// status App (Single instance)
module statusApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-status-app-deployment'
  params: {
    name: 'nostria-status'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-status:latest'
    customDomainName: 'status.nostria.app'
    appSettings: [
      {
        name: 'DB_PATH'
        value: '/home/data'
      }
      {
        name: 'DATA_RETENTION_DAYS'
        value: '14'
      }
      {
        name: 'CHECK_INTERVAL_MS'
        value: '600000'
      }
    ]
  }
}

// Certificate for status App
module statusAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-status-app-cert-deployment'
  params: {
    name: 'nostria-status'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'status.nostria.app'
    containerAppId: statusApp.outputs.id
  }
  dependsOn: [statusApp]
}

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name

// Only output these if primary region (eu)
output centralBackupStorageName string = centralBackupStorage.outputs.name
output centralBackupShareName string = centralBackupStorage.outputs.fileShareName
