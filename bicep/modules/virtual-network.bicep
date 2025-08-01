@description('Name of the virtual network')
param vnetName string

@description('Location for the virtual network')
param location string = resourceGroup().location

@description('Address space for the virtual network')
param addressSpace string = '10.0.0.0/16'

@description('VM subnet address prefix')
param vmSubnetPrefix string = '10.0.1.0/24'

@description('Tags to apply to the resources')
param tags object = {}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    subnets: [
      {
        name: 'vm-subnet'
        properties: {
          addressPrefix: vmSubnetPrefix
        }
      }
    ]
  }
}

// Outputs
output vnetId string = virtualNetwork.id
output vnetName string = virtualNetwork.name
output vmSubnetId string = virtualNetwork.properties.subnets[0].id
