// PostgreSQL role assignment module for Azure AD authentication
param postgresqlServerName string
param principalId string
param principalType string = 'ServicePrincipal'

// Get a reference to the PostgreSQL server
resource postgresqlServer 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' existing = {
  name: postgresqlServerName
}

// Create Azure AD administrator for the PostgreSQL server
// This allows Azure AD principals to connect to the database
resource postgresqlADAdmin 'Microsoft.DBforPostgreSQL/flexibleServers/administrators@2023-12-01-preview' = {
  parent: postgresqlServer
  name: principalId
  properties: {
    principalName: principalId
    principalType: principalType
    tenantId: subscription().tenantId
  }
}

output administratorId string = postgresqlADAdmin.id
output administratorName string = postgresqlADAdmin.name
