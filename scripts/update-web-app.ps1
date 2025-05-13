<#
.SYNOPSIS
    Updates the container image for specified Azure Web Apps for containers.
.DESCRIPTION
    This script connects to Azure using Azure CLI and updates the containerImage setting
    for the specified Web Apps to deploy the latest image.
.PARAMETER WebAppNames
    Array of Azure Web App names to update.
.PARAMETER ResourceGroup
    The name of the Azure resource group containing the Web Apps.
.PARAMETER ContainerImage
    The full container image name and tag to deploy.
.EXAMPLE
    .\update-discovery-relays.ps1 -WebAppNames @("relay1", "relay2") -ResourceGroup "nostria-rg" -ContainerImage "myregistry.azurecr.io/myimage:latest"
#>

param(
    [Parameter(Mandatory = $true)]
    [string[]]$WebAppNames,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory = $true)]
    [string]$ContainerImage
)

# Function to check if Azure CLI is installed
function Test-AzCliInstalled {
    try {
        $azVersion = az version
        Write-Host "Azure CLI is installed." -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        return $false
    }
}

# Function to check if user is logged in to Azure
function Test-AzCliLoggedIn {
    try {
        $account = az account show | ConvertFrom-Json
        Write-Host "Logged in to Azure as: $($account.user.name) (Subscription: $($account.name))" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "Not logged in to Azure." -ForegroundColor Yellow
        return $false
    }
}

# Function to update Web App container image
function Update-WebAppContainerImage {
    param(
        [string]$WebAppName,
        [string]$ResourceGroup,
        [string]$ContainerImage
    )

    try {
        Write-Host "Updating $WebAppName with image: $ContainerImage..." -ForegroundColor Cyan
        
        # Update the container image setting
        az webapp config container set --name $WebAppName `
                                      --resource-group $ResourceGroup `
                                      --container-image-name $ContainerImage `
                                      --output none
        
        # Restart the web app to ensure changes take effect
        az webapp restart --name $WebAppName --resource-group $ResourceGroup --output none
        
        Write-Host "Successfully updated $WebAppName" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Error "Failed to update $WebAppName. Error: $_"
        return $false
    }
}

# Main script execution
function Main {
    # Check prerequisites
    if (-not (Test-AzCliInstalled)) {
        exit 1
    }

    # Check login status, prompt for login if needed
    if (-not (Test-AzCliLoggedIn)) {
        Write-Host "Please log in to Azure..." -ForegroundColor Yellow
        az login
        
        # Check again after login attempt
        if (-not (Test-AzCliLoggedIn)) {
            Write-Error "Login failed. Exiting script."
            exit 1
        }
    }

    # Display summary of what will be updated
    Write-Host "`nPreparing to update the following Web Apps with image: $ContainerImage" -ForegroundColor Cyan
    foreach ($webApp in $WebAppNames) {
        Write-Host "  - $webApp" -ForegroundColor White
    }

    # Confirm before proceeding
    $confirmation = Read-Host -Prompt "`nDo you want to continue? (y/n)"
    if ($confirmation -ne 'y') {
        Write-Host "Operation cancelled." -ForegroundColor Yellow
        exit 0
    }

    # Update each web app
    $successCount = 0
    foreach ($webApp in $WebAppNames) {
        $result = Update-WebAppContainerImage -WebAppName $webApp -ResourceGroup $ResourceGroup -ContainerImage $ContainerImage
        if ($result) {
            $successCount++
        }
    }

    # Display summary
    Write-Host "`n====== Summary ======" -ForegroundColor Cyan
    Write-Host "Total Web Apps: $($WebAppNames.Count)" -ForegroundColor White
    Write-Host "Successfully updated: $successCount" -ForegroundColor Green
    if ($successCount -lt $WebAppNames.Count) {
        Write-Host "Failed updates: $($WebAppNames.Count - $successCount)" -ForegroundColor Red
    }
}

# Execute main function
Main
