@description('Notification Hub namespace name')
param namespaceName string

@description('Notification Hub name')
param hubName string

@description('Azure region for Notification Hub resources')
param location string = resourceGroup().location

resource notificationHubNamespace 'Microsoft.NotificationHubs/namespaces@2023-09-01' = {
  name: namespaceName
  location: location
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    zoneRedundancy: 'Disabled'
  }
}

resource notificationHub 'Microsoft.NotificationHubs/namespaces/notificationHubs@2023-09-01' = {
  name: hubName
  parent: notificationHubNamespace
  location: location
}

output namespaceId string = notificationHubNamespace.id
output namespaceName string = notificationHubNamespace.name
output notificationHubId string = notificationHub.id
output notificationHubName string = notificationHub.name
