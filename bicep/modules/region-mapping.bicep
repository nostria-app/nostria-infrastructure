// Region mapping module
// Maps region codes to Azure locations and domain prefixes

@description('Region code to get mapping for (e.g., "eu", "us", "as", etc.)')
param regionCode string

// Define mapping of region codes to Azure locations
var regionLocationMap = {
  eu: 'westeurope'        // Amsterdam, Netherlands
  us: 'centralus'         // Iowa, US
  as: 'southeastasia'     // Singapore
  af: 'southafricanorth'  // Johannesburg, South Africa
  sa: 'brazilsouth'       // São Paulo, Brazil
  au: 'australiaeast'     // Sydney, Australia
  jp: 'japaneast'         // Tokyo, Japan
  cn: 'chinanorth'        // Beijing, China (May not be available)
  in: 'centralindia'      // Pune, India
  me: 'uaenorth'          // Abu Dhabi, UAE
}

// Define mapping of region codes to human-readable names
var regionNameMap = {
  eu: 'Europe'
  us: 'USA'
  as: 'Asia'
  af: 'Africa'
  sa: 'South America'
  au: 'Australia'
  jp: 'Japan'
  cn: 'China'
  in: 'India'
  me: 'Middle East'
}

// Get the Azure location for the given region code
// Default to westeurope if region code is not found
var location = contains(regionLocationMap, regionCode) ? regionLocationMap[regionCode] : 'westeurope'

// Get the domain prefix for the given region code (e.g., 'discovery-eu')
var domainPrefix = regionCode

// Output the mapped values
output location string = location
output regionName string = contains(regionNameMap, regionCode) ? regionNameMap[regionCode] : 'Unknown'
output domainPrefix string = domainPrefix
