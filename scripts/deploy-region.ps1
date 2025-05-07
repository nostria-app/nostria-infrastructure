[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ParameterFilePath = "..\bicep\region.bicepparam",
    
    [Parameter(Mandatory=$false)]
    [string[]]$Regions,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

function Write-StatusMessage {
    param (
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info"
    )
    $color = switch ($Type) {
        "Info" { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
    }
    Write-Host $Message -ForegroundColor $color
}

# Get the script's directory to use as reference for resolving paths
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir

function Ensure-BicepInstalled {
    $bicepInPath = $null
    try { $bicepInPath = Get-Command bicep -ErrorAction SilentlyContinue } catch {}
    if (-not $bicepInPath) {
        Write-StatusMessage "Bicep not found in PATH. Installing Bicep..." -Type Warning
        $installPath = "$env:USERPROFILE\.bicep"
        $installDir = New-Item -ItemType Directory -Path $installPath -Force
        $bicepPath = "$installPath\bicep.exe"
        Write-StatusMessage "Downloading Bicep installer..." -Type Info
        $bicepUrl = "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe"
        $webClient = New-Object System.Net.WebClient
        try {
            $webClient.DownloadFile($bicepUrl, $bicepPath)
            Write-StatusMessage "Bicep downloaded successfully." -Type Success
            $env:PATH += ";$installPath"
            Write-StatusMessage "Added Bicep to PATH for current session." -Type Success
            try {
                $bicepVersion = & $bicepPath --version
                Write-StatusMessage "Bicep installed successfully. Version: $bicepVersion" -Type Success
            } catch {
                Write-StatusMessage "Failed to run Bicep after installation. Error: $_" -Type Error
                throw "Failed to install Bicep properly"
            }
        } catch {
            Write-StatusMessage "Failed to download Bicep. Error: $_" -Type Error
            throw "Failed to download Bicep installer"
        }
    } else {
        try {
            $bicepVersion = & bicep --version
            Write-StatusMessage "Bicep is already installed. Version: $bicepVersion" -Type Info
        } catch {
            Write-StatusMessage "Bicep is installed but there was an error running it. Error: $_" -Type Warning
        }
    }
}

try { Ensure-BicepInstalled } catch {
    Write-StatusMessage "Failed to ensure Bicep is installed. Error: $_" -Type Error
    Write-StatusMessage "Please install Bicep manually from https://aka.ms/bicep-install" -Type Error
    exit 1
}

# Resolve template and parameter file paths using absolute paths
$bicepTemplate = Join-Path -Path $repoRoot -ChildPath "bicep\region.bicep" 
$bicepParamFile = Join-Path -Path $repoRoot -ChildPath $ParameterFilePath.TrimStart('.\').TrimStart('..')

# Verify that template files exist
if (-not (Test-Path -Path $bicepTemplate)) {
    Write-StatusMessage "Bicep template file not found at: $bicepTemplate" -Type Error
    exit 1
}

if (-not (Test-Path -Path $bicepParamFile)) {
    Write-StatusMessage "Parameter file not found at: $bicepParamFile" -Type Error
    exit 1
}

Write-StatusMessage "Using Bicep template: $bicepTemplate" -Type Info
Write-StatusMessage "Using parameter file: $bicepParamFile" -Type Info

# Read deployRegions from the bicep parameter file
$deployRegions = @()

try {
    # Use Bicep CLI to read the parameters file
    Write-StatusMessage "Reading parameters from $bicepParamFile using Bicep CLI..." -Type Info
    $bicepParamJson = bicep build-params $bicepParamFile --stdout | ConvertFrom-Json
    if ($bicepParamJson.parameters.deployRegions.value) {
        $deployRegions = $bicepParamJson.parameters.deployRegions.value
        Write-StatusMessage "Successfully parsed regions from Bicep param file using Bicep CLI" -Type Success
    }
} catch {
    Write-StatusMessage "Bicep CLI parsing failed, will try regex fallback... Error: $_" -Type Warning
}

# Fallback: If Bicep CLI couldn't parse the parameter file, use regex
if ($deployRegions.Count -eq 0) {
    try {
        Write-StatusMessage "Using regex fallback to parse parameters..." -Type Info
        $paramContent = Get-Content -Path $bicepParamFile -Raw
        if ($paramContent -match 'param deployRegions\s*=\s*\[(.*?)\]') {
            $regionBlock = $matches[1]
            $regionLines = $regionBlock -split "[\r\n]+"
            foreach ($line in $regionLines) {
                $clean = $line.Trim() -replace "'", '' -replace '"', '' -replace ",", ''
                if ($clean -and -not $clean.StartsWith('//')) {
                    $deployRegions += $clean
                }
            }
            Write-StatusMessage "Successfully parsed regions using regex fallback" -Type Success
        }
    } catch {
        Write-StatusMessage "Regex fallback failed to parse deployRegions. Error: $_" -Type Error
    }
}

# Override with command line parameters if provided
if ($Regions -and $Regions.Count -gt 0) {
    Write-StatusMessage "Overriding regions from parameter file with command line parameters" -Type Info
    $deployRegions = $Regions
}

if ($deployRegions.Count -eq 0) {
    Write-StatusMessage "No deployment regions found. Please specify regions in the parameter file or via -Regions parameter." -Type Error
    exit 1
}

Write-StatusMessage "Deploying to regions: $($deployRegions -join ', ')" -Type Info

# Process each region for deployment
foreach ($region in $deployRegions) {
    $resourceGroupName = "nostria-$region"
    
    # Create the resource group if it doesn't exist
    try {
        $rg = Get-AzResourceGroup -Name $resourceGroupName -ErrorAction SilentlyContinue
        if (-not $rg) {
            Write-StatusMessage "Creating resource group $resourceGroupName..." -Type Info
            # Map region code to Azure location
            $regionLocationMap = @{
                "eu" = "westeurope"; "af" = "southafricanorth"; "us" = "centralus"; 
                "as" = "southeastasia"; "sa" = "brazilsouth"; "au" = "australiaeast"; 
                "jp" = "japaneast"; "cn" = "chinanorth"; "in" = "centralindia"; 
                "me" = "uaenorth"
            }
            $location = $regionLocationMap[$region]
            if (-not $location) { $location = "westeurope" }
            New-AzResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop
            Write-StatusMessage "Resource group $resourceGroupName created in $location." -Type Success
        } else {
            Write-StatusMessage "Resource group $resourceGroupName already exists." -Type Info
        }
    } catch {
        Write-StatusMessage "Failed to create or check resource group $resourceGroupName. Error: $_" -Type Error
        Write-StatusMessage "Make sure you're logged into Azure with the correct subscription." -Type Warning
        continue
    }
    
    # Deploy the Bicep template for this region
    if ($WhatIf) {
        Write-StatusMessage "Validating deployment for region $region (what-if)..." -Type Info
        try {
            $whatIfParams = @{
                ResourceGroupName = $resourceGroupName
                TemplateFile = $bicepTemplate
                TemplateParameterFile = $bicepParamFile
                currentRegion = $region
                WhatIf = $true
                ErrorAction = 'Stop'
            }
            Write-StatusMessage "Using parameters: $(ConvertTo-Json $whatIfParams -Compress)" -Type Info
            $whatIfResult = New-AzResourceGroupDeployment @whatIfParams
            Write-StatusMessage "What-If validation completed for region $region." -Type Success
        } catch {
            Write-StatusMessage "What-If validation failed for region $region. Error: $_" -Type Error
            continue
        }
    } else {
        Write-StatusMessage "Starting deployment of infrastructure to $resourceGroupName (region: $region)..." -Type Info
        try {
            $deploymentParams = @{
                ResourceGroupName = $resourceGroupName
                TemplateFile = $bicepTemplate
                TemplateParameterFile = $bicepParamFile
                currentRegion = $region
                ErrorAction = 'Stop'
            }
            $deployment = New-AzResourceGroupDeployment @deploymentParams
            if ($deployment.ProvisioningState -eq "Succeeded") {
                Write-StatusMessage "Deployment to $region succeeded!" -Type Success
            } else {
                Write-StatusMessage "Deployment to $region failed. Status: $($deployment.ProvisioningState)" -Type Error
            }
        } catch {
            Write-StatusMessage "Failed to deploy to $region. Error: $_" -Type Error
            continue
        }
    }
}

Write-StatusMessage "`nDeployment process completed!" -Type Success