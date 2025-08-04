using './vm-relay.bicep'

param currentRegion = 'eu'
param location = 'westeurope'
param baseAppName = 'nostria'
param vmSize = 'Standard_B2s'
param adminUsername = 'azureuser'
param vmRelayCount = 1

param relayNames = [
  'ribo', 'rilo', 'rifu', 'rixi', 'rova', 'ryma', 'robo', 'ruku', 'raze', 'ruby'
  'ramu', 'rizo', 'rika', 'rulo', 'ruvi', 'rino', 'riby', 'rask', 'rofo', 'rilz'
  'rudo', 'remo', 'rinz', 'rupi', 'rozi', 'ruco', 'rima', 'ropi', 'ruzo', 'riku'
  'riry', 'riso', 'ruzz', 'ropo', 'ruzi', 'rilv', 'rork', 'ramy', 'rozo', 'rimp'
  'runo', 'ripp', 'rino', 'riko', 'rufo', 'repo', 'romy', 'rilz', 'raku', 'rumo'
]

// SSH Public Key - Replace with your actual public key
param sshPublicKey = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-ssh-public-key-here'

param tags = {
  Environment: 'Production'
  Application: 'NostriaRelay'
  DeploymentType: 'VM'
  Region: 'EU'
}
