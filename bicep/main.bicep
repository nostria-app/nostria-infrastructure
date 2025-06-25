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
    name: 'nostriabakst'
    location: location
  }
}

// Deploy Key Vault for storing application secrets
module keyVault 'modules/key-vault.bicep' = {
  name: '${baseAppName}-key-vault-deployment'
  params: {
    keyVaultName: '${baseAppName}-kv'
    location: location
  }
}

// Deploy storage account for status app data
module statusStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-status-storage-deployment'
  params: {
    name: 'nostriastatusst'
    location: location
  }
}

module mainStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-main-storage-deployment'
  params: {
    name: 'nostriast'
    location: location
  }
}

// Deploy Cosmos DB for the application
module cosmosDb 'modules/cosmos-db.bicep' = {
  name: '${baseAppName}-cosmos-db-deployment'
  params: {
    name: 'nostria'
    location: location
    enableServerless: true
    enableFreeTier: false
    defaultConsistencyLevel: 'Session'
  }
}

// Website App (Single instance)
module websiteApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-web-app-deployment'
  params: {
    name: 'nostria-web'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-website:latest'
    customDomainName: 'www.nostria.app'
    appSettings: []
  }
}

// Certificate for Website App
module websiteAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-web-app-cert-deployment'
  params: {
    name: 'nostria-web'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'www.nostria.app'
  }
  dependsOn: [websiteApp]
}

// Main App (Single instance)
module mainApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-app-deployment'
  params: {
    name: 'nostria'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria:latest'
    customDomainName: 'nostria.app'
    appSettings: []
  }
}

// Certificate for Main App
module mainAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-app-cert-deployment'
  params: {
    name: 'nostria'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'nostria.app'
  }
  dependsOn: [mainApp]
}

// Metadata App (Single instance)
module metadataApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-metadata-app-deployment'
  params: {
    name: 'nostria-metadata-app'
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
    name: 'nostria-metadata-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'metadata.nostria.app'
  }
  dependsOn: [metadataApp]
}

// Find App (Single instance)
module findApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-find-app-deployment'
  params: {
    name: 'nostria-find-app'
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
    name: 'nostria-find-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'find.nostria.app'
  }
  dependsOn: [findApp]
}

// Service App (Single instance)
module serviceApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-service-app-deployment'
  params: {
    name: 'nostria-service'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-service:latest'
    customDomainName: 'api.nostria.app'
    storageAccountName: mainStorage.outputs.name
    appSettings: [
      {
        name: 'VAPID_SUBJECT'
        value: 'mailto:nostriapp@gmail.com'
      }
      {
        name: 'PUBLIC_VAPID_KEY'
        value: 'BGlnJ82dweHfLKdW2mMOLhYOj1teZ6aiFpkoPLaS5NcEqqPl2WVLMnm2EPo82C9ShWvziiEETuv5nEJYeKN1mX8'
      }
      {
        name: 'PRIVATE_VAPID_KEY'
        value: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.keyVaultName};SecretName=private-vapid-key)'
      }
      {
        name: 'NOTIFICATION_API_KEY'
        value: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.keyVaultName};SecretName=notification-api-key)'
      }
      // {
      //   name: 'AZURE_COSMOSDB_CONNECTION_STRING'
      //   value: '@Microsoft.KeyVault(VaultName=${keyVault.outputs.keyVaultName};SecretName=database-connection-string)'
      // }
      {
        name: 'AZURE_COSMOSDB_ENDPOINT'
        value: 'https://nostria.documents.azure.com:443/'
      }
    ]
  }
}

// Certificate for service App
module serviceAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-service-app-cert-deployment'
  params: {
    name: 'nostria-service'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'api.nostria.app'
  }
  dependsOn: [serviceApp]
}

module serviceAppStorageRoleAssignment1 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-service-storage-role-assignment1'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: serviceApp.outputs.webAppPrincipalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Blob Storage: Storage Blob Data Contributor
  }
}

module serviceAppStorageRoleAssignment2 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-service-storage-role-assignment2'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: serviceApp.outputs.webAppPrincipalId
    roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Table Storage: Storage Table Data Contributor
  }
}

module serviceAppStorageRoleAssignment3 'modules/role-assignment.bicep' = {
  name: '${baseAppName}-service-storage-role-assignment3'
  params: {
    storageAccountName: mainStorage.outputs.name
    principalId: serviceApp.outputs.webAppPrincipalId
    roleDefinitionId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // File Shares: Storage File Data SMB Share Contributor
  }
}

// Grant notification app access to Key Vault secrets
module serviceAppKeyVaultRoleAssignment 'modules/key-vault-role-assignment.bicep' = {
  name: '${baseAppName}-service-keyvault-role-assignment'
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: serviceApp.outputs.webAppPrincipalId
    roleDefinitionId: '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
  }
}

// Grant service app access to Cosmos DB with built-in Data Contributor role
module serviceAppCosmosDbRoleAssignment 'modules/cosmos-db-role-assignment.bicep' = {
  name: '${baseAppName}-service-cosmosdb-role-assignment'
  params: {
    cosmosDbAccountName: cosmosDb.outputs.name
    principalId: serviceApp.outputs.webAppPrincipalId
    useBuiltInDataContributorRole: true
  }
}

// Service App (Single instance)
// module serviceApp 'modules/container-app.bicep' = {
//   name: '${baseAppName}-service-app-deployment'
//   params: {
//     name: 'nostria-service'
//     location: location
//     appServicePlanId: appServicePlan.outputs.id
//     containerImage: 'ghcr.io/nostria-app/nostria-service:latest'
//     customDomainName: 'service.nostria.app'
//     storageAccountName: mainStorage.outputs.name
//     appSettings: []
//   }
// }

// // Certificate for service App
// module serviceAppCert 'modules/container-app-certificate.bicep' = {
//   name: '${baseAppName}-service-app-cert-deployment'
//   params: {
//     name: 'nostria-service'
//     location: location
//     appServicePlanId: appServicePlan.outputs.id
//     customDomainName: 'service.nostria.app'
//   }
//   dependsOn: [serviceApp]
// }

// module serviceAppStorageRoleAssignment1 'modules/role-assignment.bicep' = {
//   name: '${baseAppName}-service-storage-role-assignment1'
//   params: {
//     storageAccountName: mainStorage.outputs.name
//     principalId: serviceApp.outputs.webAppPrincipalId
//     roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' // Blob Storage: Storage Blob Data Contributor
//   }
// }

// module serviceAppStorageRoleAssignment2 'modules/role-assignment.bicep' = {
//   name: '${baseAppName}-service-storage-role-assignment2'
//   params: {
//     storageAccountName: mainStorage.outputs.name
//     principalId: serviceApp.outputs.webAppPrincipalId
//     roleDefinitionId: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Table Storage: Storage Table Data Contributor
//   }
// }

// module serviceAppStorageRoleAssignment3 'modules/role-assignment.bicep' = {
//   name: '${baseAppName}-service-storage-role-assignment3'
//   params: {
//     storageAccountName: mainStorage.outputs.name
//     principalId: serviceApp.outputs.webAppPrincipalId
//     roleDefinitionId: '0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb' // File Shares: Storage File Data SMB Share Contributor
//   }
// }

// status App (Single instance)
module statusApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-status-app-deployment'
  params: {
    name: 'nostria-status-app'
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
}

// Certificate for status App
module statusAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-status-app-cert-deployment'
  params: {
    name: 'nostria-status-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'status.nostria.app'
  }
  dependsOn: [statusApp]
}

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name

// Cosmos DB outputs
output cosmosDbAccountId string = cosmosDb.outputs.id
output cosmosDbAccountName string = cosmosDb.outputs.name
output cosmosDbDocumentEndpoint string = cosmosDb.outputs.documentEndpoint
output cosmosDbPrincipalId string = cosmosDb.outputs.principalId
output cosmosDbDatabaseName string = cosmosDb.outputs.databaseName
output cosmosDbContainerName string = cosmosDb.outputs.containerName

// Only output these if primary region (eu)
output centralBackupStorageName string = centralBackupStorage.outputs.name
output centralBackupShareName string = centralBackupStorage.outputs.fileShareName
