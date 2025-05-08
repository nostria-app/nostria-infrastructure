// filepath: c:\src\github\nostria\nostria-infrastructure\bicep\modules\container-app-compose.bicep
param name string
param location string = resourceGroup().location
param appServicePlanId string
param customDomainName string = ''
param appSettings array = []
param dockerComposeYaml string
param storageAccountName string = ''
@secure()
param configYmlContent string = ''

// Get a reference to the storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' existing = if (!empty(storageAccountName)) {
  name: storageAccountName
}

// Get storage account key for initial mount but app will use managed identity later
var storageAccountKey = !empty(storageAccountName) ? storageAccount.listKeys().keys[0].value : ''

// Write config file directly to storage account using ARM template deployment
resource configFile 'Microsoft.Resources/deploymentScripts@2020-10-01' = if (!empty(configYmlContent) && !empty(storageAccountName)) {
  name: '${name}-config-deployment'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '7.5' // Using a more widely available version
    timeout: 'PT30M'
    retentionInterval: 'P1D'
    environmentVariables: [
      {
        name: 'CONFIG_CONTENT'
        secureValue: configYmlContent
      }
      {
        name: 'STORAGE_ACCOUNT_NAME'
        value: storageAccountName
      }
      {
        name: 'STORAGE_ACCOUNT_KEY'
        secureValue: storageAccountKey
      }
      {
        name: 'FILE_SHARE_NAME'
        value: 'data'
      }
    ]
    scriptContent: '''
# Print diagnostic information
Write-Output "Starting config deployment script"

# Check for required environment variables
if (-not $env:CONFIG_CONTENT) {
    Write-Error "CONFIG_CONTENT environment variable is missing"
    throw "Missing required environment variable: CONFIG_CONTENT"
}

if (-not $env:STORAGE_ACCOUNT_NAME) {
    Write-Error "STORAGE_ACCOUNT_NAME environment variable is missing"
    throw "Missing required environment variable: STORAGE_ACCOUNT_NAME"
}

if (-not $env:STORAGE_ACCOUNT_KEY) {
    Write-Error "STORAGE_ACCOUNT_KEY environment variable is missing"
    throw "Missing required environment variable: STORAGE_ACCOUNT_KEY"
}

if (-not $env:FILE_SHARE_NAME) {
    Write-Error "FILE_SHARE_NAME environment variable is missing"
    throw "Missing required environment variable: FILE_SHARE_NAME"
}

# Write config content directly to a file in the current directory
$configPath = "config.yml"
Write-Output "Writing config content to $configPath"
$env:CONFIG_CONTENT | Out-File -FilePath $configPath -Encoding utf8

if (-not (Test-Path $configPath)) {
    Write-Error "Failed to create config file at $configPath"
    throw "Config file creation failed"
}

# Get storage account context using key
Write-Output "Creating storage context for $($env:STORAGE_ACCOUNT_NAME)"
$storageContext = New-AzStorageContext -StorageAccountName $env:STORAGE_ACCOUNT_NAME -StorageAccountKey $env:STORAGE_ACCOUNT_KEY

# Check if file share exists, create if not
Write-Output "Checking if file share $($env:FILE_SHARE_NAME) exists"
$share = Get-AzStorageShare -Context $storageContext -Name $env:FILE_SHARE_NAME -ErrorAction SilentlyContinue
if ($null -eq $share) {
    Write-Output "Creating file share $($env:FILE_SHARE_NAME)"
    $share = New-AzStorageShare -Context $storageContext -Name $env:FILE_SHARE_NAME
}

# Upload config.yml to file share
Write-Output "Uploading config.yml to file share $($env:FILE_SHARE_NAME)"
Set-AzStorageFileContent -Context $storageContext -ShareName $env:FILE_SHARE_NAME -Source $configPath -Path "config.yml" -Force

# Verify upload was successful
Write-Output "Verifying file was uploaded successfully"
$fileExists = Get-AzStorageFile -Context $storageContext -ShareName $env:FILE_SHARE_NAME -Path "config.yml" -ErrorAction SilentlyContinue
if ($null -eq $fileExists) {
    Write-Error "Failed to verify config.yml was uploaded to storage"
    throw "File upload verification failed"
} else {
    Write-Output "config.yml successfully uploaded to $($env:FILE_SHARE_NAME) share"
}

# Cleanup the local file after successful upload
if (Test-Path $configPath) {
    Remove-Item -Path $configPath -Force
    Write-Output "Removed temporary local config file"
}

# Return success
$DeploymentScriptOutputs = @{}
$DeploymentScriptOutputs['configFileUploaded'] = $true
$DeploymentScriptOutputs['timestamp'] = Get-Date -Format o
    '''
    cleanupPreference: 'OnSuccess'
  }
}

// Main container app resource with docker-compose support
resource containerApp 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'app,linux,container'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      http20Enabled: true
      alwaysOn: true
      appSettings: concat(
        appSettings,
        [
          {
            name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
            value: 'true'
          }
          {
            name: 'DOCKER_REGISTRY_SERVER_URL'
            value: 'https://ghcr.io'
          }
          {
            name: 'DOCKER_ENABLE_CI'
            value: 'true'
          }
        ],
        !empty(storageAccountName)
          ? [
              {
                name: 'WEBSITES_CONTAINER_START_TIME_LIMIT'
                value: '600' // Increase container start time limit to allow mount to complete
              }
              {
                name: 'CUSTOM_MOUNT_PATH'
                value: '/data'
              }
              {
                name: 'AZURE_STORAGE_ACCOUNT' // Standard Azure env variable name
                value: storageAccountName
              }
              {
                name: 'WEBSITES_MOUNT_ENABLED'
                value: '1' // Ensure storage mounting is explicitly enabled
              }
            ]
          : []
      )
      linuxFxVersion: 'COMPOSE|${base64(dockerComposeYaml)}'
      // Configure Azure Storage mount when storage account name is provided
      azureStorageAccounts: !empty(storageAccountName)
        ? {
            media: {
              type: 'AzureFiles'
              accountName: storageAccountName
              mountPath: '/data'
              shareName: 'data'
              accessKey: storageAccountKey // Required for initial mount, app will use managed identity later
            }
          }
        : {}
    }
  }
  dependsOn: [
    configFile
  ]
}

// Hostname binding for custom domain
resource hostnameBinding 'Microsoft.Web/sites/hostNameBindings@2024-04-01' = if (!empty(customDomainName)) {
  parent: containerApp
  name: customDomainName
  properties: {
    hostNameType: 'Verified'
    sslState: 'Disabled'
    thumbprint: ''
    siteName: name
    azureResourceType: 'Website'
    customHostNameDnsRecordType: 'CName'
  }
}

output id string = containerApp.id
output name string = containerApp.name
output hostname string = containerApp.properties.defaultHostName
output webAppPrincipalId string = containerApp.identity.principalId
output hostnameBindingResourceId string = !empty(customDomainName) ? hostnameBinding.id : ''
