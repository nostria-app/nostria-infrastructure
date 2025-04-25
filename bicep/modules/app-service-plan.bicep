param name string
param location string = resourceGroup().location
param kind string = 'linux'
param sku object = {
  name: 'B1'
  tier: 'Basic'
}
param reserved bool = true

resource appServicePlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: name
  location: location
  kind: kind
  sku: sku
  properties: {
    reserved: reserved // Required for Linux plans
  }
}

output id string = appServicePlan.id
output name string = appServicePlan.name