param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Parameters for configuring app instances
param relayCount int = 1
param mediaCount int = 1

// Server name arrays
var relayNames = [
  'Ribo', 'Rilo', 'Rifu', 'Rixi', 'Rova', 'Ryma', 'Robo', 'Ruku', 'Raze', 'Ruby'
  'Ramu', 'Rizo', 'Rika', 'Rulo', 'Ruvi', 'Rino', 'Riby', 'Rask', 'Rofo', 'Rilz'
  'Rudo', 'Remo', 'Rinz', 'Rupi', 'Rozi', 'Ruco', 'Rima', 'Ropi', 'Ruzo', 'Riku'
  'Riry', 'Riso', 'Ruzz', 'Ropo', 'Ruzi', 'Rilv', 'Rork', 'Ramy', 'Rozo', 'Rimp'
  'Runo', 'Ripp', 'Rino', 'Riko', 'Rufo', 'Repo', 'Romy', 'Rilz', 'Raku', 'Rumo'
]

var mediaNames = [
  'Mibo', 'Milo', 'Mifu', 'Mixi', 'Mova', 'Myma', 'Mobo', 'Muku', 'Maze', 'Miby'
  'Mamu', 'Mizo', 'Mika', 'Mulo', 'Muvi', 'Mino', 'Miby', 'Mask', 'Mofo', 'Milz'
  'Mudo', 'Memo', 'Minz', 'Mupi', 'Mozi', 'Muco', 'Mima', 'Mopi', 'Muzo', 'Miku'
  'Miry', 'Miso', 'Muzz', 'Mopo', 'Muzi', 'Milv', 'Mork', 'Mamy', 'Mozo', 'Mimp'
  'Muno', 'Mipp', 'Mino', 'Miko', 'Mufo', 'Mepo', 'Momy', 'Milz', 'Maku', 'Mumo'
]

// Deploy the main App Service Plan for all container apps
module appServicePlan 'modules/app-service-plan.bicep' = {
  name: '${baseAppName}-plan-deployment'
  params: {
    name: '${baseAppName}-linux-plan'
    location: location
  }
}

var discoveryStorageAccountName = '${baseAppName}discovery'

// Discovery App (Single instance)
module discoveryApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-discovery-app-deployment'
  params: {
    name: 'nostria-discovery'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'discovery.nostria.app'
    storageAccountName: discoveryStorageAccountName
    appSettings: [
      {
        name: 'CUSTOM_SETTING'
        value: 'value'
      }
      {
        name: 'Lmdb__MaxReaders'
        value: 4096
      }
      {
        name: 'Lmdb__SizeInMb'
        value: 1024
      }
      {
        name: 'Relay__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Relay__PostingPolicy'
        value: 'https://discovery.nostria.com/posting-policy'
      }
      {
        name: 'Relay__PrivacyPolicy'
        value: 'https://discovery.nostria.com/privacy-policy'
      }
    ]
  }
}

// Certificate for Discovery App
module discoveryAppCert 'modules/container-app-certificate.bicep' = {
  name: '${baseAppName}-discovery-app-cert-deployment'
  params: {
    name: 'nostria-discovery'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: 'discovery.nostria.app'
    containerAppId: discoveryApp.outputs.id
  }
  dependsOn: [discoveryApp]
}

// Storage Account for Discovery
module discoveryStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-discovery-storage-deployment'
  params: {
    name: discoveryStorageAccountName
    location: location
    webAppPrincipalId: discoveryApp.outputs.webAppPrincipalId
  }
}

// Backup Storage for Discovery
module discoveryBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-discovery-backup-deployment'
  params: {
    sourceStorageAccountName: discoveryStorageAccountName
    location: location
  }
}

var websiteStorageAccountName = '${baseAppName}website'

// Website App (Single instance)
module websiteApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-website-app-deployment'
  params: {
    name: 'nostria-website'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-website:latest'
    customDomainName: 'www.nostria.app'
    storageAccountName: websiteStorageAccountName
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

// Storage Account for Website
module websiteStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-website-storage-deployment'
  params: {
    name: websiteStorageAccountName
    location: location
    webAppPrincipalId: websiteApp.outputs.webAppPrincipalId
  }
}

// Backup Storage for Website
module websiteBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-website-backup-deployment'
  params: {
    sourceStorageAccountName: websiteStorageAccountName
    location: location
  }
}

var appStorageAccountName = '${baseAppName}app'

// Main App (Single instance)
module mainApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-main-app-deployment'
  params: {
    name: 'nostria-app'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria:b4e68ee403f5b2909de329633bd473f891493b1d'
    customDomainName: 'nostria.app'
    storageAccountName: appStorageAccountName
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

// Storage Account for Main app site
module appStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-app-storage-deployment'
  params: {
    name: appStorageAccountName
    location: location
    webAppPrincipalId: mainApp.outputs.webAppPrincipalId
  }
}

// Backup Storage for Main app site
module appBackupStorage 'modules/backup.bicep' = {
  name: '${baseAppName}-app-backup-deployment'
  params: {
    sourceStorageAccountName: appStorageAccountName
    location: location
  }
}

var metadataStorageAccountName = '${baseAppName}metadata'

// Metadata App (Single instance)
module metadataApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-metadata-app-deployment'
  params: {
    name: 'nostria-metadata'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-metadata:latest'
    customDomainName: 'metadata.nostria.app'
    storageAccountName: metadataStorageAccountName
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
    containerAppId: websiteApp.outputs.id
  }
  dependsOn: [metadataApp]
}

// Storage Account for Website
module metadataStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-metadata-storage-deployment'
  params: {
    name: metadataStorageAccountName
    location: location
    webAppPrincipalId: metadataApp.outputs.webAppPrincipalId
  }
}


// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name
output discoveryAppUrl string = 'https://${discoveryApp.outputs.hostname}'
output websiteAppUrl string = 'https://${websiteApp.outputs.hostname}'
output mainAppUrl string = 'https://${mainApp.outputs.hostname}'
output relayAppUrls array = [for i in range(0, relayCount): 'https://${toLower(relayNames[i])}.nostria.app']
output mediaAppUrls array = [for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}.nostria.app']
