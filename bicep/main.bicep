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

// Deploy storage account for status app data
module statusStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-status-storage-deployment'
  params: {
    name: 'nostriastatussa'
    location: location
  }
}

module mainStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-main-storage-deployment'
  params: {
    name: 'nostriasa'
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

// Find App (Single instance)
module findApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-find-app-deployment'
  params: {
    name: 'nostria-find'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-find:latest'
    customDomainName: 'find.nostria.app'
    appSettings: []
  }
}

// Certificate for Find App
module findAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-find-app-cert-deployment'
  params: {
    name: 'nostria-find'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'find.nostria.app'
    containerAppId: findApp.outputs.id
  }
  dependsOn: [findApp]
}

// notification App (Single instance)
module notificationApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-notification-app-deployment'
  params: {
    name: 'nostria-notification'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-notification:latest'
    customDomainName: 'notification.nostria.app'
    storageAccountName: mainStorage.outputs.name
    appSettings: []
  }
}

// Certificate for notification App
module notificationAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-notification-app-cert-deployment'
  params: {
    name: 'nostria-notification'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'notification.nostria.app'
    containerAppId: notificationApp.outputs.id
  }
  dependsOn: [notificationApp]
}

module notificationAppStorageRoleAssignment1 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-notification-storage-role-assignment'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: notificationApp.outputs.webAppPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Blob Storage: Storage Blob Data Contributor
  }
}

module notificationAppStorageRoleAssignment2 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-notification-storage-role-assignment'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: notificationApp.outputs.webAppPrincipalId
    roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Table Storage: Storage Table Data Contributor
  }
}

module notificationAppStorageRoleAssignment3 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-notification-storage-role-assignment'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: notificationApp.outputs.webAppPrincipalId
    roleDefinitionId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // File Shares: Storage File Data SMB Share Contributor
  }
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
    storageAccountName: statusStorage.outputs.name
    appSettings: [
      {
        name: 'DB_PATH'
        value: '/app/data'
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

// Assign Storage File Data SMB Share Contributor role to discovery app
module statusAppStorageRoleAssignment 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-status-storage-role-assignment'
  params: {
    storageAccountName: statusStorage.outputs.name
    principalId: statusApp.outputs.webAppPrincipalId
    // Default role will be used (Storage File Data SMB Share Contributor)
    // If Status app needs Blob Storage access, change to:
    // roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Storage Blob Data Contributor
  }
  dependsOn: [statusApp, statusStorage]
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
