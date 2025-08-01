using './vm-relay.bicep'

param currentRegion = 'eu'
param location = 'westeurope'
param baseAppName = 'nostria'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'
param vmRelayCount = 1

// SSH Public Key - Replace with your actual public key
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-ssh-public-key-here'

param tags = {
  Environment: 'Production'
  Application: 'NostriaRelay'
  DeploymentType: 'VM'
  Region: 'EU'
}
