using 'region.bicep'

param currentRegion = 'eu'
param baseAppName = 'nostria'
param defaultRelayCount = 1
param defaultMediaCount = 1

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

param relayCountPerRegion = {
  af: 1
  eu: 1
  us: 1
}
param mediaCountPerRegion = {
  af: 1
  eu: 1
  us: 1
}

param relayNames = [
  'Ribo', 'Rilo', 'Rifu', 'Rixi', 'Rova', 'Ryma', 'Robo', 'Ruku', 'Raze', 'Ruby'
  'Ramu', 'Rizo', 'Rika', 'Rulo', 'Ruvi', 'Rino', 'Riby', 'Rask', 'Rofo', 'Rilz'
  'Rudo', 'Remo', 'Rinz', 'Rupi', 'Rozi', 'Ruco', 'Rima', 'Ropi', 'Ruzo', 'Riku'
  'Riry', 'Riso', 'Ruzz', 'Ropo', 'Ruzi', 'Rilv', 'Rork', 'Ramy', 'Rozo', 'Rimp'
  'Runo', 'Ripp', 'Rino', 'Riko', 'Rufo', 'Repo', 'Romy', 'Rilz', 'Raku', 'Rumo'
]

param mediaNames = [
  'Mibo', 'Milo', 'Mifu', 'Mixi', 'Mova', 'Myma', 'Mobo', 'Muku', 'Maze', 'Miby'
  'Mamu', 'Mizo', 'Mika', 'Mulo', 'Muvi', 'Mino', 'Miby', 'Mask', 'Mofo', 'Milz'
  'Mudo', 'Memo', 'Minz', 'Mupi', 'Mozi', 'Muco', 'Mima', 'Mopi', 'Muzo', 'Miku'
  'Miry', 'Miso', 'Muzz', 'Mopo', 'Muzi', 'Milv', 'Mork', 'Mamy', 'Mozo', 'Mimp'
  'Muno', 'Mipp', 'Mino', 'Miko', 'Mufo', 'Mepo', 'Momy', 'Milz', 'Maku', 'Mumo'
]
