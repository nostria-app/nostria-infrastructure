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

@description('Subnet resource ID for the VM network interface')
param subnetId string

@description('Network security group resource ID')
param networkSecurityGroupId string

@description('Storage account name for VM diagnostics')
param diagnosticsStorageAccountName string

@description('Tags to apply to the resources')
param tags object = {}

@description('Force extension update by changing this value')
param forceUpdate string = 'v1'

// Variables
var nicName = '${vmName}-nic'
var osDiskName = '${vmName}-os-disk'
var dataDiskName = '${vmName}-data-disk'
var publicIpName = '${vmName}-pip'

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

// Data disk for strfry database (32GB for VM relays)
resource dataDisk 'Microsoft.Compute/disks@2023-04-02' = {
  name: dataDiskName
  location: location
  tags: tags
  sku: {
    name: 'StandardSSD_LRS'
  }
  properties: {
    diskSizeGB: 32
    creationData: {
      createOption: 'Empty'
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
            id: subnetId
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
      dataDisks: [
        {
          name: dataDiskName
          lun: 0
          createOption: 'Attach'
          caching: 'ReadWrite'
          managedDisk: {
            id: dataDisk.id
            storageAccountType: 'StandardSSD_LRS'
          }
        }
      ]
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
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: [
        'https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/refs/heads/main/scripts/vm-setup.sh'
      ]
    }
    protectedSettings: {
      commandToExecute: 'bash vm-setup.sh ${forceUpdate}'
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
