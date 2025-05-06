param location string = resourceGroup().location
param baseAppName string = 'nostria'

// Parameters for configuring app instances
param relayCount int = 1
param mediaCount int = 1

// Server name arrays - adding missing commas between array entries
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

// Deploy a centralized backup storage account - KEEPING THIS ONE
module centralBackupStorage 'modules/central-backup.bicep' = {
  name: '${baseAppName}-central-backup-deployment'
  params: {
    name: 'nostriabak'
    location: location
  }
}

// Discovery App (Single instance)
module discoveryApp 'modules/container-app.bicep' = {
  name: '${baseAppName}-discovery-app-deployment'
  params: {
    name: 'nostria-discovery'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/discovery-relay:latest'
    customDomainName: 'discovery.nostria.app'
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
        name: 'Lmdb__DatabasePath'
        value: '/home/data'
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
    appSettings: []
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

// Relay Apps (Multiple instances based on relayCount)
module relayApps 'modules/container-app.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-deployment'
  params: {
    name: 'nostria-relay-${toLower(relayNames[i])}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    containerImage: 'ghcr.io/nostria-app/nostria-relay:latest'
    customDomainName: '${toLower(relayNames[i])}.nostria.app'
    appSettings: [
      {
        name: 'Relay__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Relay__PostingPolicy'
        value: 'https://relay.nostria.com/posting-policy'
      }
      {
        name: 'Relay__PrivacyPolicy'
        value: 'https://relay.nostria.com/privacy-policy'
      }
    ]
  }
}]

// Certificates for Relay Apps
module relayAppsCerts 'modules/container-app-certificate.bicep' = [for i in range(0, relayCount): {
  name: '${baseAppName}-relay-${toLower(relayNames[i])}-cert-deployment'
  params: {
    name: 'nostria-relay-${toLower(relayNames[i])}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(relayNames[i])}.nostria.app'
    containerAppId: relayApps[i].outputs.id
  }
  dependsOn: [relayApps]
}]

// Media Apps (Multiple instances based on mediaCount) using docker-compose
module mediaApps 'modules/container-app-compose.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-deployment'
  params: {
    name: 'nostria-media-${toLower(mediaNames[i])}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(mediaNames[i])}.nostria.app'
    dockerComposeYaml: '''
version: '3'
services:
  media-app:
    image: ghcr.io/nostria-app/nostria-media:latest
    restart: always
    ports:
      - "3000:3000"
    volumes:
      - ${HOME}/data:/app/data
    environment:
      - Media__StoragePath=/app/data
      - Media__Contact=17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515
      - Media__PrivacyPolicy=https://media.nostria.com/privacy-policy
  media-processor:
    image: ghcr.io/nostria-app/nostria-media-processor:latest
    restart: always
    depends_on:
      - media-app
    volumes:
      - ${HOME}/data:/app/data
'''
    appSettings: [
      {
        name: 'WEBSITES_PORT'
        value: '3000'
      }
      {
        name: 'Media__StoragePath'
        value: '/app/data'
      }
      {
        name: 'Media__Contact'
        value: '17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515'
      }
      {
        name: 'Media__PrivacyPolicy'
        value: 'https://media.nostria.com/privacy-policy'
      }
    ]
  }
}]

// Certificates for Media Apps
module mediaAppsCerts 'modules/container-app-certificate.bicep' = [for i in range(0, mediaCount): {
  name: '${baseAppName}-media-${toLower(mediaNames[i])}-cert-deployment'
  params: {
    name: 'nostria-media-${toLower(mediaNames[i])}'
    location: location
    appServicePlanId: appServicePlan.outputs.id
    customDomainName: '${toLower(mediaNames[i])}.nostria.app'
    containerAppId: mediaApps[i].outputs.id
  }
  dependsOn: [mediaApps]
}]

// Outputs to provide easy access to important resource information
output appServicePlanId string = appServicePlan.outputs.id
output appServicePlanName string = appServicePlan.outputs.name
output centralBackupStorageName string = centralBackupStorage.outputs.name
output centralBackupShareName string = centralBackupStorage.outputs.fileShareName
output discoveryAppUrl string = 'https://${discoveryApp.outputs.hostname}'
output websiteAppUrl string = 'https://${websiteApp.outputs.hostname}'
output mainAppUrl string = 'https://${mainApp.outputs.hostname}'
output relayAppUrls array = [for i in range(0, relayCount): 'https://${toLower(relayNames[i])}.nostria.app']
output mediaAppUrls array = [for i in range(0, mediaCount): 'https://${toLower(mediaNames[i])}.nostria.app']
