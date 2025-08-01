@description('The current region being deployed (e.g., "eu", "af")')
param currentRegion string

@description('Location for the VM resources')
param location string = resourceGroup().location

@description('Base name for the application')
param baseAppName string = 'nostria'

@description('SSH public key for VM access')
@secure()
param sshPublicKey string

@description('VM size for the relay servers')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VMs')
param adminUsername string = 'azureuser'

@description('Number of VM relay servers to deploy')
param vmRelayCount int = 1

@description('Tags to apply to the resources')
param tags object = {
  Environment: 'Production'
  Application: 'NostriaRelay'
  DeploymentType: 'VM'
}

// Variables
var vmRelayBaseName = '${baseAppName}-${currentRegion}-vm-relay'
var vnetName = '${baseAppName}-${currentRegion}-vnet'
var nsgName = '${baseAppName}-${currentRegion}-vm-nsg'
var storageAccountName = 'nostria${currentRegion}vmst'

// Deploy storage account for VM diagnostics
module diagnosticsStorage 'modules/storage-account.bicep' = {
  name: '${baseAppName}-${currentRegion}-vm-diagnostics-storage-deployment'
  params: {
    name: storageAccountName
    location: location
  }
}

// Deploy Virtual Network
module virtualNetwork 'modules/virtual-network.bicep' = {
  name: '${baseAppName}-${currentRegion}-vnet-deployment'
  params: {
    vnetName: vnetName
    location: location
    tags: tags
  }
}

// Deploy Network Security Group
module networkSecurityGroup 'modules/network-security-group.bicep' = {
  name: '${baseAppName}-${currentRegion}-nsg-deployment'
  params: {
    nsgName: nsgName
    location: location
    tags: tags
  }
}

// Deploy VM Relay Servers
module vmRelayServers 'modules/virtual-machine.bicep' = [for i in range(0, vmRelayCount): {
  name: '${vmRelayBaseName}-${i + 1}-deployment'
  params: {
    vmName: '${vmRelayBaseName}-${i + 1}'
    location: location
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    virtualNetworkId: virtualNetwork.outputs.vnetId
    networkSecurityGroupId: networkSecurityGroup.outputs.nsgId
    diagnosticsStorageAccountName: diagnosticsStorage.outputs.name
    tags: tags
  }
}]

// Outputs
output vmRelayNames array = [for i in range(0, vmRelayCount): vmRelayServers[i].outputs.vmName]
output vmRelayPublicIps array = [for i in range(0, vmRelayCount): vmRelayServers[i].outputs.publicIpAddress]
output vmRelayFqdns array = [for i in range(0, vmRelayCount): vmRelayServers[i].outputs.fqdn]
output vnetId string = virtualNetwork.outputs.vnetId
output nsgId string = networkSecurityGroup.outputs.nsgId
