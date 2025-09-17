using './main.bicep'

param baseAppName = 'nostria'
// PostgreSQL deployment is disabled by default
param deployPostgreSQL = false
// PostgreSQL admin password will be provided during deployment via command line parameter when deployPostgreSQL is true
// Example: --parameters deployPostgreSQL=true postgresqlAdminPassword='your-secure-password'
