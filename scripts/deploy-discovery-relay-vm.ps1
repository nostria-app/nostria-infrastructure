[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory=$false)]
    [string]$Region = "eu",
    
    [Parameter(Mandatory=$false)]
    [string]$SshPublicKeyPath = "$env:USERPROFILE\.ssh\id_rsa.pub",
    
    [Parameter(Mandatory=$false)]
    [string]$VmSize = "Standard_B2s",
    
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

# Set default resource group name if not provided
if ([string]::IsNullOrEmpty($ResourceGroupName)) {
    $ResourceGroupName = "nostria-$Region-discovery"
}

Write-StatusMessage "Starting Discovery Relay VM deployment for region: $Region" -Type Info

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
$deploymentName = "nostria-discovery-relay-vm-$Region-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$templateFile = Join-Path $repoRoot "bicep\discovery-relay.bicep"
$forceUpdateValue = "v$(Get-Date -Format 'yyyyMMddHHmmss')"

Write-StatusMessage "Deployment name: $deploymentName" -Type Info
Write-StatusMessage "Template file: $templateFile" -Type Info
Write-StatusMessage "Region: $Region, Location: $Location, VM Size: $VmSize" -Type Info

# Run what-if first if requested or validate before deployment
if ($WhatIf) {
    Write-StatusMessage "Running what-if analysis..." -Type Info
    try {
        $whatIfParams = @(
            '--resource-group', $ResourceGroupName,
            '--name', $deploymentName,
            '--template-file', $templateFile,
            '--parameters',
            "currentRegion=$Region",
            "location=$Location",
            "vmSize=$VmSize",
            "forceUpdate=$forceUpdateValue",
            "sshPublicKey=$sshPublicKey"
        )
        
        az deployment group what-if @whatIfParams
        Write-StatusMessage "What-if analysis completed successfully!" -Type Success
        exit 0
    } catch {
        Write-StatusMessage "What-if analysis failed: $($_.Exception.Message)" -Type Error
        exit 1
    }
}

try {
    # Build the deployment command and parameters for logging
    $azParams = @(
        '--resource-group', $ResourceGroupName,
        '--name', $deploymentName,
        '--template-file', $templateFile,
        '--parameters',
        "currentRegion=$Region",
        "location=$Location",
        "vmSize=$VmSize",
        "forceUpdate=$forceUpdateValue",
        "sshPublicKey=$sshPublicKey"
    )
    
    Write-StatusMessage "About to run: az deployment group create $($azParams -join ' ')" -Type Info

    # Run the az deployment group create command
    Write-StatusMessage "Running deployment..." -Type Info
    $azResult = & az deployment group create @azParams 2>&1
    $azExitCode = $LASTEXITCODE
    
    if ($azExitCode -eq 0) {
        Write-StatusMessage "Deployment completed successfully!" -Type Success
        
        # Retry logic for deployment status check
        $maxRetries = 5
        $retryDelay = 5
        $foundDeployment = $false
        
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            Write-StatusMessage "Checking deployment status (attempt $attempt/$maxRetries)..." -Type Info
            $deploymentStatus = az deployment group show --resource-group $ResourceGroupName --name $deploymentName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $foundDeployment = $true
                break
            } else {
                Start-Sleep -Seconds $retryDelay
            }
        }
        
        if ($foundDeployment) {
            Write-StatusMessage "Retrieving deployment outputs..." -Type Info
            $outputs = az deployment group show --resource-group $ResourceGroupName --name $deploymentName --query properties.outputs | ConvertFrom-Json
            
            if ($outputs.discoveryRelayName) {
                Write-StatusMessage "Discovery Relay VM Name:" -Type Success
                Write-Host "  - $($outputs.discoveryRelayName.value)" -ForegroundColor Green
            }
            if ($outputs.discoveryRelayPublicIp) {
                Write-StatusMessage "Discovery Relay Public IP:" -Type Success
                Write-Host "  - $($outputs.discoveryRelayPublicIp.value)" -ForegroundColor Green
            }
            if ($outputs.discoveryRelayFqdn) {
                Write-StatusMessage "Discovery Relay FQDN:" -Type Success
                Write-Host "  - $($outputs.discoveryRelayFqdn.value)" -ForegroundColor Green
            }
        } else {
            Write-StatusMessage "ERROR: Deployment not found after $maxRetries attempts. It may have failed to start or was never created." -Type Error
            Write-StatusMessage "No deployment is visible in the Azure Portal for this resource group and name." -Type Error
            Write-StatusMessage "Output from last status check:" -Type Warning
            $deploymentStatus | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            Write-StatusMessage "Full deployment output:" -Type Warning
            $azResult | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
            Write-StatusMessage "Please check the Azure Portal Activity Log for errors, and verify your permissions and template validity." -Type Error
        }
        
        Write-StatusMessage "" -Type Info
        Write-StatusMessage "Next steps:" -Type Info
        Write-StatusMessage "1. Update DNS records to point discovery.$Region.nostria.app to the VM public IP" -Type Info
        Write-StatusMessage "2. The discovery relay should be accessible at https://discovery.$Region.nostria.app once DNS propagates" -Type Info
        Write-StatusMessage "3. You can SSH to the VM using: ssh azureuser@<VM-Public-IP>" -Type Info
        Write-StatusMessage "4. Check relay status: /usr/local/bin/strfry-health-check.sh" -Type Info
        Write-StatusMessage "5. Monitor logs: sudo journalctl -u strfry -f" -Type Info
        Write-StatusMessage "" -Type Info
        Write-StatusMessage "Discovery Relay Configuration:" -Type Info
        Write-StatusMessage "- Config file: /etc/strfry/strfry.conf (uses discovery-relay config)" -Type Info
        Write-StatusMessage "- Database: /var/lib/strfry/db" -Type Info
        Write-StatusMessage "- Service: systemctl status strfry" -Type Info
        
    } else {
        Write-StatusMessage "Deployment failed with exit code: $azExitCode" -Type Error
        Write-StatusMessage "Error details:" -Type Error
        $azResult | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
} catch {
    Write-StatusMessage "Deployment failed with exception: $($_.Exception.Message)" -Type Error
    if ($_.Exception.InnerException) {
        Write-StatusMessage "Inner exception: $($_.Exception.InnerException.Message)" -Type Error
    }
    exit 1
}
