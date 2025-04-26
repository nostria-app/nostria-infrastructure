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

# Create resource group if it doesn't exist
$resourceGroup = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$resourceGroup) {
    Write-Host "Creating resource group '$ResourceGroupName' in location '$Location'..." -ForegroundColor Yellow
    New-AzResourceGroup -Name $ResourceGroupName -Location $Location
    Write-Host "Resource group created." -ForegroundColor Green
} else {
    Write-Host "Using existing resource group '$ResourceGroupName'." -ForegroundColor Green
}

# Deploy Bicep template
$deploymentName = "nostria-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Host "Starting deployment: $deploymentName..." -ForegroundColor Yellow

$deploymentResult = New-AzResourceGroupDeployment `
  -Name $deploymentName `
  -ResourceGroupName $ResourceGroupName `
  -TemplateFile "$PSScriptRoot\..\bicep\main.bicep" `
  -location $Location `
  -relayCount $RelayCount `
  -mediaCount $MediaCount `
  -Verbose

if ($deploymentResult.ProvisioningState -eq "Succeeded") {
    Write-Host "Deployment successful!" -ForegroundColor Green
    Write-Host "App Service Plan: $($deploymentResult.Outputs.appServicePlanName.Value)" -ForegroundColor Cyan
    Write-Host "Discovery App URL: $($deploymentResult.Outputs.discoveryAppUrl.Value)" -ForegroundColor Cyan
    Write-Host "About App URL: $($deploymentResult.Outputs.aboutAppUrl.Value)" -ForegroundColor Cyan
    Write-Host "Main App URL: $($deploymentResult.Outputs.mainAppUrl.Value)" -ForegroundColor Cyan
    
    Write-Host "Relay App URLs:" -ForegroundColor Cyan
    foreach ($url in $deploymentResult.Outputs.relayAppUrls.Value) {
        Write-Host "- $url" -ForegroundColor Cyan
    }
    
    Write-Host "Media App URLs:" -ForegroundColor Cyan
    foreach ($url in $deploymentResult.Outputs.mediaAppUrls.Value) {
        Write-Host "- $url" -ForegroundColor Cyan
    }
} else {
    Write-Host "Deployment failed: $($deploymentResult.Error)" -ForegroundColor Red
}