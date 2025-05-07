[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ParameterFilePath,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

# Find the script directory
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir

# If no parameter file specified, use the default
if (-not $ParameterFilePath) {
    $ParameterFilePath = Join-Path -Path $repoRoot -ChildPath "bicep\main.bicepparam"
}

# Ensure parameter file exists
if (-not (Test-Path $ParameterFilePath)) {
    Write-Error "Parameter file not found: $ParameterFilePath"
    exit 1
}

# Import the core deployment script
$deployScriptPath = Join-Path -Path $scriptDir -ChildPath "deploy.ps1"

if (-not (Test-Path $deployScriptPath)) {
    Write-Error "Core deployment script not found at: $deployScriptPath"
    exit 1
}

# Read deployRegions from the bicep parameter file
$deployRegions = @()
try {
    # Use Bicep CLI to read the parameters file - this works with newer Bicep versions
    Write-Host "Reading parameters from $ParameterFilePath using Bicep CLI..." -ForegroundColor Cyan
    $bicepParamJson = bicep build-params $ParameterFilePath --stdout | ConvertFrom-Json
    if ($bicepParamJson.parameters.deployRegions.value) {
        $deployRegions = $bicepParamJson.parameters.deployRegions.value
        Write-Host "Successfully parsed regions from Bicep param file using Bicep CLI" -ForegroundColor Green
    }
} catch {
    Write-Host "Bicep CLI parsing failed, will try regex fallback... Error: $_" -ForegroundColor Yellow
}

# Fallback: If Bicep CLI couldn't parse the parameter file, use regex
if ($deployRegions.Count -eq 0) {
    try {
        Write-Host "Using regex fallback to parse parameters..." -ForegroundColor Cyan
        $paramContent = Get-Content -Path $ParameterFilePath -Raw
        if ($paramContent -match 'param deployRegions\s*=\s*\[(.*?)\]') {
            $regionBlock = $matches[1]
            $regionLines = $regionBlock -split "[\r\n]+"
            foreach ($line in $regionLines) {
                $clean = $line.Trim() -replace "'", '' -replace '"', '' -replace ",", ''
                if ($clean -and -not $clean.StartsWith('//')) {
                    $deployRegions += $clean
                }
            }
            Write-Host "Successfully parsed regions using regex fallback" -ForegroundColor Green
        }
    } catch {
        Write-Host "Regex fallback failed to parse deployRegions. Error: $_" -ForegroundColor Red
    }
}

if ($deployRegions.Count -eq 0) {
    Write-Host "No deployment regions found in parameter file. Using default regions: eu, af" -ForegroundColor Yellow
    $deployRegions = @("eu", "af")
}

Write-Host "Preparing to deploy to the following regions: $($deployRegions -join ', ')" -ForegroundColor Cyan
Write-Host "This will create/update resources in the following resource groups: $($deployRegions | ForEach-Object { "nostria-$_" } | Join-String -Separator ', ')" -ForegroundColor Cyan

$confirmed = $false
if (-not $WhatIf) {
    $confirmation = Read-Host "Do you want to proceed with the deployment? (y/n)"
    $confirmed = $confirmation -eq "y" -or $confirmation -eq "yes"
} else {
    $confirmed = $true
    Write-Host "Running in What-If mode (no actual deployments will be made)" -ForegroundColor Yellow
}

if (-not $confirmed) {
    Write-Host "Deployment cancelled by user." -ForegroundColor Yellow
    exit 0
}

$results = @{}

foreach ($region in $deployRegions) {
    Write-Host "`n=== Starting deployment for region: $region ===" -ForegroundColor Cyan
    
    $deployArgs = @{
        ParameterFilePath = $ParameterFilePath
        Regions = @($region)
    }
    
    if ($WhatIf) {
        $deployArgs.Add("WhatIf", $true)
    }
    
    try {
        # Call the deploy.ps1 script for each region
        & $deployScriptPath @deployArgs
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Deployment for region $region completed successfully" -ForegroundColor Green
            $results[$region] = "Success"
        } else {
            Write-Host "Deployment for region $region failed with exit code $LASTEXITCODE" -ForegroundColor Red
            $results[$region] = "Failed"
        }
    } catch {
        Write-Host "Error during deployment to region $region`: $_" -ForegroundColor Red
        $results[$region] = "Error: $_"
    }
}

# Display deployment summary
Write-Host "`n=== Deployment Summary ===" -ForegroundColor Cyan
foreach ($region in $deployRegions) {
    $status = $results[$region]
    $color = if ($status -eq "Success") { "Green" } else { "Red" }
    Write-Host "Region $region`: $status" -ForegroundColor $color
}

$successCount = ($results.Values | Where-Object { $_ -eq "Success" }).Count
if ($successCount -eq $deployRegions.Count) {
    Write-Host "`nAll deployments completed successfully!" -ForegroundColor Green
} else {
    Write-Host "`nDeployment completed with issues. $successCount out of $($deployRegions.Count) regions deployed successfully." -ForegroundColor Yellow
}
