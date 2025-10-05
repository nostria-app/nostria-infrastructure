using 'region.bicep'

param currentRegion = 'eu'
param baseAppName = 'nostria'
param defaultMediaCount = 1
param keyVaultName = 'nostria-kv'
param globalResourceGroupName = 'nostria-global'
param createKeyVaultRbacAssignments = false // Disable since we already have manual assignments

param appServicePlanSkus = {
  eu: {
    name: 'B3'
    tier: 'Basic'
  }
  us: {
    name: 'B3'
    tier: 'Basic'
  }
  af: {
    name: 'B2'
    tier: 'Basic'
  }
}

param mediaCountPerRegion = {
  af: 1
  eu: 1
  us: 1
}

param mediaNames = [
  'Mibo', 'Milo', 'Mifu', 'Mixi', 'Mova', 'Myma', 'Mobo', 'Muku', 'Maze', 'Miby'
  'Mamu', 'Mizo', 'Mika', 'Mulo', 'Muvi', 'Mino', 'Miby', 'Mask', 'Mofo', 'Milz'
  'Mudo', 'Memo', 'Minz', 'Mupi', 'Mozi', 'Muco', 'Mima', 'Mopi', 'Muzo', 'Miku'
  'Miry', 'Miso', 'Muzz', 'Mopo', 'Muzi', 'Milv', 'Mork', 'Mamy', 'Mozo', 'Mimp'
  'Muno', 'Mipp', 'Mino', 'Miko', 'Mufo', 'Mepo', 'Momy', 'Milz', 'Maku', 'Mumo'
]
