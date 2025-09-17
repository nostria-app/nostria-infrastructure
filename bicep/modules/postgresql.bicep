// Azure Database for PostgreSQL Flexible Server module
// This module creates a PostgreSQL Flexible Server with security best practices

param serverName string
param location string = resourceGroup().location

@description('Administrator username for the PostgreSQL server')
param administratorLogin string = 'nostria_admin'

@description('Administrator password for the PostgreSQL server')
@secure()
param administratorPassword string

@description('The name of the database to create')
param databaseName string = 'nostria'

@description('The version of PostgreSQL to use')
@allowed(['11', '12', '13', '14', '15', '16', '17'])
param postgresqlVersion string = '17'

@description('The SKU name for the PostgreSQL server')
@allowed(['Standard_B1ms', 'Standard_B2s', 'Standard_B2ms', 'Standard_B4ms', 'Standard_D2s_v3', 'Standard_D4s_v3', 'Standard_D8s_v3'])
param skuName string = 'Standard_B1ms'

@description('The tier of the PostgreSQL server')
@allowed(['Burstable', 'GeneralPurpose', 'MemoryOptimized'])
param skuTier string = 'Burstable'

@description('Storage size in GB')
@minValue(32)
@maxValue(32767)
param storageSizeGB int = 32

@description('Storage performance tier')
@allowed(['P4', 'P6', 'P10', 'P15', 'P20', 'P30', 'P40', 'P50', 'P60', 'P70', 'P80'])
param storageTier string = 'P4'

@description('Backup retention period in days')
@minValue(7)
@maxValue(35)
param backupRetentionDays int = 7

@description('Enable geo-redundant backup')
param geoRedundantBackup bool = false

@description('Enable high availability')
param highAvailabilityEnabled bool = false

@description('Enable public network access')
param publicNetworkAccess bool = true

// PostgreSQL Flexible Server
resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    version: postgresqlVersion
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword
    storage: {
      storageSizeGB: storageSizeGB
      tier: storageTier
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: backupRetentionDays
      geoRedundantBackup: geoRedundantBackup ? 'Enabled' : 'Disabled'
    }
    highAvailability: {
      mode: highAvailabilityEnabled ? 'ZoneRedundant' : 'Disabled'
    }
    network: {
      publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    }
    // Enable Azure Active Directory authentication
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Enabled'
      tenantId: subscription().tenantId
    }
    // Enable SSL enforcement
    dataEncryption: {
      type: 'SystemManaged'
    }
  }
}

// Note: SSL is enabled by default in PostgreSQL Flexible Server and cannot be disabled
// Server parameters like 'ssl' are read-only and managed automatically
// Only configure parameters that are actually user-configurable

// Allow Azure services to access the server
resource firewallRuleAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-12-01-preview' = if (publicNetworkAccess) {
  parent: postgresqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Create the main database
resource postgresqlDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-12-01-preview' = {
  parent: postgresqlServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Outputs
output serverId string = postgresqlServer.id
output serverName string = postgresqlServer.name
output serverFQDN string = postgresqlServer.properties.fullyQualifiedDomainName
output databaseName string = postgresqlDatabase.name
output administratorLogin string = administratorLogin

// Connection string template for use in Key Vault secret (PostgreSQL URI format)
output connectionStringTemplate string = 'postgresql://${administratorLogin}:{password}@${postgresqlServer.properties.fullyQualifiedDomainName}:5432/${databaseName}?sslmode=require'
