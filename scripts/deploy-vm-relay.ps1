[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "nostria-eu",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu",
    
    [Parameter(Mandatory=$false)]
    [string]$SshPublicKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub",
    
    [Parameter(Mandatory=$false)]
    [string]$VmSize = "Standard_B2s",
    
    [Parameter(Mandatory=$false)]
    [int]$VmRelayCount = 1,
    
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

Write-StatusMessage "Starting VM Relay deployment for region: $Region" -Type Info

# Check if SSH public key exists
if (-not (Test-Path $SshPublicKeyPath)) {
    Write-StatusMessage "SSH public key not found at: $SshPublicKeyPath" -Type Error
    Write-StatusMessage "Please generate an SSH key pair or provide the correct path" -Type Error
    Write-StatusMessage "To generate a new key pair, run: ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\id_rsa" -Type Info
    exit 1
}

# Read SSH public key
try {
    $sshPublicKey = Get-Content $SshPublicKeyPath -Raw
    $sshPublicKey = $sshPublicKey.Trim()
    Write-StatusMessage "SSH public key loaded successfully" -Type Success
} catch {
    Write-StatusMessage "Failed to read SSH public key: $($_.Exception.Message)" -Type Error
    exit 1
}

# Check if Azure CLI is logged in
try {
    $account = az account show | ConvertFrom-Json
    Write-StatusMessage "Logged in to Azure as: $($account.user.name) (Subscription: $($account.name))" -Type Success
} catch {
    Write-StatusMessage "Not logged in to Azure. Please run 'az login'" -Type Error
    exit 1
}

# Check if resource group exists, create if it doesn't
Write-StatusMessage "Checking if resource group '$ResourceGroupName' exists..." -Type Info
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    Write-StatusMessage "Resource group '$ResourceGroupName' does not exist. Creating..." -Type Warning
    if (-not $WhatIf) {
        az group create --name $ResourceGroupName --location $Location
        Write-StatusMessage "Resource group '$ResourceGroupName' created successfully" -Type Success
    } else {
        Write-StatusMessage "[WHAT-IF] Would create resource group '$ResourceGroupName' in '$Location'" -Type Info
    }
} else {
    Write-StatusMessage "Resource group '$ResourceGroupName' already exists" -Type Success
}

# Prepare deployment parameters
$deploymentName = "nostria-vm-relay-$Region-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$templateFile = Join-Path $repoRoot "bicep\vm-relay.bicep"
$forceUpdateValue = "v$(Get-Date -Format 'yyyyMMddHHmmss')"

# Build deployment command
$deployCommand = @(
    "az", "deployment", "group", "create"
    "--resource-group", $ResourceGroupName
    "--name", $deploymentName
    "--template-file", $templateFile
    "--parameters"
    "currentRegion=$Region"
    "location=$Location"
    "vmSize=$VmSize"
    "vmRelayCount=$VmRelayCount"
    "forceUpdate=$forceUpdateValue"
    "sshPublicKey=$sshPublicKey"
)

if ($WhatIf) {
    $deployCommand += "--what-if"
    Write-StatusMessage "Running what-if deployment..." -Type Info
} else {
    Write-StatusMessage "Starting deployment..." -Type Info
}

Write-StatusMessage "Deployment command: $($deployCommand -join ' ')" -Type Info

try {
    # Execute deployment
    $result = & $deployCommand[0] $deployCommand[1..$($deployCommand.Length-1)]
    
    if ($LASTEXITCODE -eq 0) {
        if (-not $WhatIf) {
            Write-StatusMessage "Deployment completed successfully!" -Type Success
            
            # Get deployment outputs
            Write-StatusMessage "Retrieving deployment outputs..." -Type Info
            $outputs = az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query properties.outputs | ConvertFrom-Json
            
            if ($outputs.vmRelayNames) {
                Write-StatusMessage "VM Relay Names:" -Type Success
                $outputs.vmRelayNames.value | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
            }
            
            if ($outputs.vmRelayPublicIps) {
                Write-StatusMessage "VM Relay Public IPs:" -Type Success
                $outputs.vmRelayPublicIps.value | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
            }
            
            if ($outputs.vmRelayFqdns) {
                Write-StatusMessage "VM Relay FQDNs:" -Type Success
                $outputs.vmRelayFqdns.value | ForEach-Object { Write-Host "  - $_" -ForegroundColor Green }
            }
            
            Write-StatusMessage "" -Type Info
            Write-StatusMessage "Next steps:" -Type Info
            Write-StatusMessage "1. Update DNS records to point ribo.eu.nostria.app to the VM public IP" -Type Info
            Write-StatusMessage "2. The relay should be accessible at https://ribo.eu.nostria.app once DNS propagates" -Type Info
            Write-StatusMessage "3. You can SSH to the VM using: ssh $($env:USERNAME)@<VM-Public-IP>" -Type Info
            Write-StatusMessage "4. Check relay status: /usr/local/bin/strfry-health-check.sh" -Type Info
        } else {
            Write-StatusMessage "What-if deployment completed successfully!" -Type Success
        }
    } else {
        Write-StatusMessage "Deployment failed with exit code: $LASTEXITCODE" -Type Error
        Write-StatusMessage "Error output: $result" -Type Error
        exit 1
    }
} catch {
    Write-StatusMessage "Deployment failed: $($_.Exception.Message)" -Type Error
    exit 1
}
