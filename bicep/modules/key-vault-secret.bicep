// Key Vault secret module for storing individual secrets
param keyVaultName string
param secretName string
@secure()
param secretValue string
param contentType string = 'application/text'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: secretValue
    contentType: contentType
  }
}

output secretName string = secret.name
output secretUri string = secret.properties.secretUri
output secretUriWithVersion string = secret.properties.secretUriWithVersion
