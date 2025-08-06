using './discovery-relay.bicep'

param currentRegion = 'eu'
param location = 'westeurope'
param baseAppName = 'nostria'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'

// SSH Public Key - Replace with your actual public key
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-ssh-public-key-here'

param tags = {
  Environment: 'Production'
  Application: 'NostriaDiscoveryRelay'
  DeploymentType: 'VM'
  Region: 'EU'
}
