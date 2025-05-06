param(
  [Parameter(Mandatory=$false)]
  [string]$Location = "westeurope",
  
  [Parameter(Mandatory=$true)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [int]$RelayCount = 1,
  
  [Parameter(Mandatory=$false)]
  [int]$MediaCount = 1
)

# Combine ResourceGroupName and Location for the actual resource group name
$actualResourceGroupName = "$ResourceGroupName-$Location"

# Create resource group if it doesn't exist
$resourceGroup = az group show --name $actualResourceGroupName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating resource group '$actualResourceGroupName' in location '$Location'..." -ForegroundColor Yellow
    az group create --name $actualResourceGroupName --location $Location
    Write-Host "Resource group created." -ForegroundColor Green
} else {
    Write-Host "Using existing resource group '$actualResourceGroupName'." -ForegroundColor Green
}

# Deploy Bicep template
$deploymentName = "nostria-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

# Using az deployment group create instead of New-AzResourceGroupDeployment
$deploymentResult = az deployment group create `
  --name $deploymentName `
  --resource-group $actualResourceGroupName `
  --template-file "$PSScriptRoot\..\bicep\main.bicep" `
  --parameters location=$Location relayCount=$RelayCount mediaCount=$MediaCount `
  --verbose

# Parse the JSON output 
$deployment = $deploymentResult | ConvertFrom-Json

if ($deployment.properties.provisioningState -eq "Succeeded") {
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host "App Service Plan: $($deployment.properties.outputs.appServicePlanName.value)" -ForegroundColor Cyan
    Write-Host "Discovery App URL: $($deployment.properties.outputs.discoveryAppUrl.value)" -ForegroundColor Cyan
    Write-Host "About App URL: $($deployment.properties.outputs.websiteAppUrl.value)" -ForegroundColor Cyan
    Write-Host "Main App URL: $($deployment.properties.outputs.mainAppUrl.value)" -ForegroundColor Cyan
    
    Write-Host "Relay App URLs:" -ForegroundColor Cyan
    foreach ($url in $deployment.properties.outputs.relayAppUrls.value) {
        Write-Host "- $url" -ForegroundColor Cyan
    }
    
    Write-Host "Media App URLs:" -ForegroundColor Cyan
    foreach ($url in $deployment.properties.outputs.mediaAppUrls.value) {
        Write-Host "- $url" -ForegroundColor Cyan
    }
} else {
    Write-Host "Deployment failed: $($deployment.properties.error)" -ForegroundColor Red
    exit 1
}