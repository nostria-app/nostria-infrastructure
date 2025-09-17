// Module to create a PostgreSQL connection string and store it in Key Vault
// This automatically generates the connection string using the PostgreSQL server details

param keyVaultName string
param postgresqlServerFQDN string
param postgresqlDatabaseName string
param postgresqlAdminLogin string
@secure()
param postgresqlAdminPassword string
param secretName string = 'postgresql-connection-string'
param contentType string = 'PostgreSQL Connection String'

// Reference the existing Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Generate the complete connection string in PostgreSQL URI format
var connectionString = 'postgresql://${postgresqlAdminLogin}:${postgresqlAdminPassword}@${postgresqlServerFQDN}:5432/${postgresqlDatabaseName}?sslmode=require'

// Store the connection string in Key Vault
resource postgresqlConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: connectionString
    contentType: contentType
    attributes: {
      enabled: true
    }
  }
}

// Outputs
output secretName string = postgresqlConnectionSecret.name
output secretUri string = postgresqlConnectionSecret.properties.secretUri
output secretUriWithVersion string = postgresqlConnectionSecret.properties.secretUriWithVersion
output keyVaultReference string = '@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=${secretName})'
