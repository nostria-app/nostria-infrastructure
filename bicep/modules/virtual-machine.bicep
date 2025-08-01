@description('Name of the virtual machine')
param vmName string

@description('Location for the VM resources')
param location string = resourceGroup().location

@description('Size of the VM')
param vmSize string = 'Standard_B2s'

@description('Admin username for the VM')
param adminUsername string = 'azureuser'

@description('SSH public key for VM access')
@secure()
param sshPublicKey string

@description('Virtual network resource ID')
param virtualNetworkId string

@description('Subnet name within the virtual network')
param subnetName string = 'vm-subnet'

@description('Network security group resource ID')
param networkSecurityGroupId string

@description('Storage account name for VM diagnostics')
param diagnosticsStorageAccountName string

@description('Tags to apply to the resources')
param tags object = {}

// Variables
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-os-disk'
var publicIpName = '${vmName}-pip'

// Get the subnet reference
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-05-01' existing = {
  name: split(virtualNetworkId, '/')[8]
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

// Public IP for the VM
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmName
    }
  }
}

// Network interface for the VM
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroupId
    }
  }
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: osDiskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 30
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: 'https://${diagnosticsStorageAccountName}.blob.${environment().suffixes.storage}/'
      }
    }
  }
}

// VM Extension for installing and configuring strfry and Caddy
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: virtualMachine
  name: 'strfry-caddy-setup'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/vm-setup.sh'
      ]
    }
    protectedSettings: {
      commandToExecute: 'bash vm-setup.sh'
    }
  }
}

// Outputs
output vmName string = virtualMachine.name
output vmId string = virtualMachine.id
output publicIpAddress string = publicIp.properties.ipAddress
output privateIpAddress string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
output principalId string = virtualMachine.identity.principalId
output fqdn string = publicIp.properties.dnsSettings.fqdn
