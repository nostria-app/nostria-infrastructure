param name string
param location string = resourceGroup().location

@description('The database account offer type')
@allowed(['Standard'])
param databaseAccountOfferType string = 'Standard'

@description('Enable serverless capacity mode')
param enableServerless bool = true

@description('The default consistency level of the Cosmos DB account')
@allowed(['Eventual', 'Session', 'BoundedStaleness', 'Strong', 'ConsistentPrefix'])
param defaultConsistencyLevel string = 'Session'

@description('Enable automatic failover for regions')
param enableAutomaticFailover bool = false

@description('Enable multiple write locations')
param enableMultipleWriteLocations bool = false

@description('Enable free tier (only one per subscription)')
param enableFreeTier bool = false

@description('Name of the database to create')
param databaseName string = 'NostriaDB'

@description('Name of the container to create')
param containerName string = 'Documents'

@description('Partition key for the container')
param partitionKeyPath string = '/id'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: name
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: databaseAccountOfferType
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: defaultConsistencyLevel
    }
    enableAutomaticFailover: enableAutomaticFailover
    enableMultipleWriteLocations: enableMultipleWriteLocations
    enableFreeTier: enableFreeTier
    capabilities: enableServerless ? [
      {
        name: 'EnableServerless'
      }
    ] : []
    disableKeyBasedMetadataWriteAccess: false
    disableLocalAuth: false
    publicNetworkAccess: 'Enabled'
    networkAclBypass: 'None'
    minimalTlsVersion: 'Tls12'
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource cosmosDatabase 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    options: enableServerless ? {} : {
      throughput: 400
    }
  }
}

resource cosmosContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: cosmosDatabase
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [partitionKeyPath]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/"_etag"/?'
          }
        ]
      }
    }
    options: enableServerless ? {} : {
      throughput: 400
    }
  }
}

output id string = cosmosAccount.id
output name string = cosmosAccount.name
output documentEndpoint string = cosmosAccount.properties.documentEndpoint
output principalId string = cosmosAccount.identity.principalId
output apiVersion string = cosmosAccount.apiVersion
output databaseName string = cosmosDatabase.name
output containerName string = cosmosContainer.name
