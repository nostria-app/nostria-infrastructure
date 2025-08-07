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

# Set default resource group name if not provided
if ([string]::IsNullOrEmpty($ResourceGroupName)) {
    $ResourceGroupName = "nostria-$Region-relays"
}

Write-StatusMessage "Starting VM Relay deployment for region: $Region" -Type Info
Write-StatusMessage "Features:" -Type Info
Write-StatusMessage "  - VM Size: $VmSize" -Type Info
Write-StatusMessage "  - VM Count: $VmRelayCount" -Type Info
Write-StatusMessage "  - OS Disk: 30GB Premium SSD" -Type Info
Write-StatusMessage "  - Data Disk: 32GB Standard SSD (for strfry database)" -Type Info
Write-StatusMessage "  - Auto-configured with strfry + Caddy" -Type Info

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

Write-StatusMessage "Deployment name: $deploymentName" -Type Info
Write-StatusMessage "Template file: $templateFile" -Type Info
Write-StatusMessage "Region: $Region, Location: $Location, VM Size: $VmSize, VM Count: $VmRelayCount" -Type Info


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
        "vmRelayCount=$VmRelayCount",
        "forceUpdate=$forceUpdateValue",
        "sshPublicKey=$sshPublicKey"
    )
    if ($WhatIf) {
        $azCmd = 'az deployment group what-if'
    } else {
        $azCmd = 'az deployment group create'
    }
    Write-StatusMessage "About to run: $azCmd $($azParams -join ' ')" -Type Info

    # Run the az deployment group create command directly (concise output)
    Write-StatusMessage "Running deployment..." -Type Info
    $azResult = & az deployment group create @azParams 2>&1
    $azExitCode = $LASTEXITCODE
    if ($azExitCode -eq 0) {
        if (-not $WhatIf) {
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
            } else {
                Write-StatusMessage "ERROR: Deployment not found after $maxRetries attempts. It may have failed to start or was never created." -Type Error
                Write-StatusMessage "No deployment is visible in the Azure Portal for this resource group and name." -Type Error
                Write-StatusMessage "Output from last status check:" -Type Warning
                $deploymentStatus | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
                Write-StatusMessage "Full deployment output (stdout):" -Type Warning
                $stdOut | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
                Write-StatusMessage "Full deployment error (stderr):" -Type Warning
                $stdErr | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
                Write-StatusMessage "Please check the Azure Portal Activity Log for errors, and verify your permissions and template validity." -Type Error
            }
            Write-StatusMessage "" -Type Info
            Write-StatusMessage "Next steps:" -Type Info
            if ($VmRelayCount -eq 1) {
                Write-StatusMessage "1. Update DNS records to point ribo.$Region.nostria.app to the VM public IP" -Type Info
                Write-StatusMessage "2. The relay should be accessible at https://ribo.$Region.nostria.app once DNS propagates" -Type Info
            } else {
                Write-StatusMessage "1. Update DNS records to point the relay domains to their respective VM public IPs:" -Type Info
                for ($i = 0; $i -lt $VmRelayCount; $i++) {
                    $relayName = @('ribo', 'rilo', 'rifu', 'rixi', 'rova', 'ryma', 'robo', 'ruku', 'raze', 'ruby')[$i]
                    Write-StatusMessage "   - $relayName.$Region.nostria.app" -Type Info
                }
                Write-StatusMessage "2. The relays should be accessible at their respective HTTPS domains once DNS propagates" -Type Info
            }
            Write-StatusMessage "3. You can SSH to the VM(s) using: ssh azureuser@<VM-Public-IP>" -Type Info
            Write-StatusMessage "4. Check relay status: /usr/local/bin/strfry-health-check.sh" -Type Info
        } else {
            Write-StatusMessage "What-if deployment completed successfully!" -Type Success
        }
    } else {
        Write-StatusMessage "Deployment failed with exit code: $exitCode" -Type Error
        if ($stdErr) {
            Write-StatusMessage "Error details (stderr):" -Type Error
            $stdErr | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        if ($stdOut) {
            Write-StatusMessage "Output details (stdout):" -Type Error
            $stdOut | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        exit 1
    }
} catch {
    Write-StatusMessage "Deployment failed with exception: $($_.Exception.Message)" -Type Error
    if ($_.Exception.InnerException) {
        Write-StatusMessage "Inner exception: $($_.Exception.InnerException.Message)" -Type Error
    }
    exit 1
}
