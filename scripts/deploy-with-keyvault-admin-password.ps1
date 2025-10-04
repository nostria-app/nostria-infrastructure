# Deploy Nostria Infrastructure with Blossom Admin Password from Key Vault
# This script demonstrates how to deploy the infrastructure with the admin password stored in Azure Key Vault

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$Location,
    
    [Parameter(Mandatory=$true)]
    [string]$BlossomAdminPassword,
    
    [Parameter(Mandatory=$false)]
    [string]$CurrentRegion = "eu"
)

Write-Host "Deploying Nostria Infrastructure with Key Vault integration..." -ForegroundColor Green

# Deploy main infrastructure (includes Key Vault)
Write-Host "1. Deploying main infrastructure with Key Vault..." -ForegroundColor Yellow
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "bicep/main.bicep" `
    --parameters blossomAdminPassword="$BlossomAdminPassword"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Main deployment failed!"
    exit 1
}

# Deploy region-specific resources
Write-Host "2. Deploying region-specific resources..." -ForegroundColor Yellow
az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file "bicep/region.bicep" `
    --parameters "bicep/region.bicepparam" `
    --parameters currentRegion="$CurrentRegion"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Region deployment failed!"
    exit 1
}

Write-Host "✅ Deployment completed successfully!" -ForegroundColor Green
Write-Host "The Blossom admin password has been stored in Key Vault and will be automatically injected into the configuration." -ForegroundColor Cyan

# Verify the Key Vault secret
Write-Host "3. Verifying Key Vault secret..." -ForegroundColor Yellow
$kvName = "nostria-kv"
$secretValue = az keyvault secret show --vault-name $kvName --name "blossom-admin-password" --query "value" -o tsv

if ($secretValue) {
    Write-Host "✅ Key Vault secret 'blossom-admin-password' exists and will be used by the media servers." -ForegroundColor Green
} else {
    Write-Warning "⚠️  Could not verify Key Vault secret. Please check the deployment."
}

Write-Host ""
Write-Host "🔑 Key Vault Integration Details:" -ForegroundColor Cyan
Write-Host "- Secret Name: blossom-admin-password" -ForegroundColor White
Write-Host "- Key Vault: $kvName" -ForegroundColor White
Write-Host "- Environment Variable: BLOSSOM_ADMIN_PASSWORD" -ForegroundColor White
Write-Host "- Config File: Uses \${BLOSSOM_ADMIN_PASSWORD} placeholder" -ForegroundColor White
Write-Host ""
Write-Host "The media servers will automatically receive the admin password via Azure App Service's Key Vault integration." -ForegroundColor Green