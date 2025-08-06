@description('The current region being deployed (e.g., "eu", "af")')
param currentRegion string

@description('Location for the VM resources')
param location string = resourceGroup().location

@description('Base name for the application')
param baseAppName string = 'nostria'

@description('SSH public key for VM access')
@secure()
param sshPublicKey string

@description('VM size for the discovery relay server')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('Tags to apply to the resources')
param tags object = {
  Environment: 'Production'
  Application: 'NostriaDiscoveryRelay'
  DeploymentType: 'VM'
}

@description('Force extension update by changing this value')
param forceUpdate string = 'v2'

// Variables
var discoveryRelayName = '${baseAppName}-${currentRegion}-discovery'
var vnetName = '${baseAppName}-${currentRegion}-discovery-vnet'
var nsgName = '${baseAppName}-${currentRegion}-discovery-nsg'
var storageAccountName = 'nostria${currentRegion}discst'

// Deploy storage account for VM diagnostics
module diagnosticsStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-${currentRegion}-discovery-diagnostics-storage-deployment'
  params: {
    name: storageAccountName
    location: location
  }
}

// Deploy Virtual Network
module virtualNetwork 'modules/virtual-network.bicep' = {
  name: '${baseAppName}-${currentRegion}-discovery-vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// Deploy Network Security Group
module networkSecurityGroup 'modules/network-security-group.bicep' = {
  name: '${baseAppName}-${currentRegion}-discovery-nsg-deployment'
  params: {
    nsgName: nsgName
    location: location
    tags: tags
  }
}

// Deploy Discovery Relay VM
module discoveryRelayServer 'modules/discovery-virtual-machine.bicep' = {
  name: '${discoveryRelayName}-vm-deployment'
  params: {
    vmName: '${discoveryRelayName}-vm'
    location: location
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: virtualNetwork.outputs.vmSubnetId
    networkSecurityGroupId: networkSecurityGroup.outputs.nsgId
    diagnosticsStorageAccountName: diagnosticsStorage.outputs.name
    forceUpdate: forceUpdate
    tags: tags
  }
}

// Outputs
output discoveryRelayName string = discoveryRelayServer.outputs.vmName
output discoveryRelayPublicIp string = discoveryRelayServer.outputs.publicIpAddress
output discoveryRelayFqdn string = discoveryRelayServer.outputs.fqdn
output dataDiskId string = discoveryRelayServer.outputs.dataDiskId
output dataDiskName string = discoveryRelayServer.outputs.dataDiskName
output vnetId string = virtualNetwork.outputs.vnetId
output nsgId string = networkSecurityGroup.outputs.nsgId
