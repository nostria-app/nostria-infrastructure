[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$VmName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory=$false)]
    [int]$DiskSizeGB = 32,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountType = "StandardSSD_LRS",
    
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

Write-StatusMessage "=== Adding Data Disk to Existing VM Relay ===" -Type Info
Write-StatusMessage "VM Name: $VmName" -Type Info
Write-StatusMessage "Disk Size: $DiskSizeGB GB" -Type Info
Write-StatusMessage "Storage Type: $StorageAccountType" -Type Info

# Check if Azure CLI is logged in
try {
    $account = az account show | ConvertFrom-Json
    Write-StatusMessage "Logged in to Azure as: $($account.user.name) (Subscription: $($account.name))" -Type Success
} catch {
    Write-StatusMessage "Not logged in to Azure. Please run 'az login'" -Type Error
    exit 1
}

# Get VM information
Write-StatusMessage "Getting VM information..." -Type Info
try {
    if ([string]::IsNullOrEmpty($ResourceGroupName)) {
        # Try to find the VM by name across all resource groups
        $vmInfo = az vm list --query "[?name=='$VmName']" | ConvertFrom-Json
        if ($vmInfo.Count -eq 0) {
            Write-StatusMessage "VM '$VmName' not found in any resource group" -Type Error
            exit 1
        } elseif ($vmInfo.Count -gt 1) {
            Write-StatusMessage "Multiple VMs found with name '$VmName'. Please specify ResourceGroupName:" -Type Warning
            $vmInfo | ForEach-Object { Write-Host "  - $($_.name) in $($_.resourceGroup)" -ForegroundColor Yellow }
            exit 1
        }
        $ResourceGroupName = $vmInfo[0].resourceGroup
        $vmLocation = $vmInfo[0].location
        Write-StatusMessage "Found VM in resource group: $ResourceGroupName" -Type Success
    } else {
        $vmInfo = az vm show --name $VmName --resource-group $ResourceGroupName | ConvertFrom-Json
        $vmLocation = $vmInfo.location
    }
    
    Write-StatusMessage "VM Location: $vmLocation" -Type Info
} catch {
    Write-StatusMessage "Failed to get VM information: $($_.Exception.Message)" -Type Error
    exit 1
}

# Check if VM already has data disks
$existingDataDisks = az vm show --name $VmName --resource-group $ResourceGroupName --query "storageProfile.dataDisks" | ConvertFrom-Json

if ($existingDataDisks.Count -gt 0) {
    Write-StatusMessage "VM already has data disks:" -Type Warning
    $existingDataDisks | ForEach-Object { 
        Write-Host "  - LUN $($_.lun): $($_.name) ($($_.diskSizeGb) GB)" -ForegroundColor Yellow 
    }
    
    $continue = Read-Host "Do you want to add another data disk? (y/N)"
    if ($continue.ToLower() -ne 'y') {
        Write-StatusMessage "Aborted by user" -Type Info
        exit 0
    }
}

# Find next available LUN
$nextLun = 0
if ($existingDataDisks.Count -gt 0) {
    $nextLun = ($existingDataDisks | Measure-Object -Property lun -Maximum).Maximum + 1
}

# Create disk name
$diskName = "$VmName-data-disk-$nextLun"

Write-StatusMessage "Creating data disk: $diskName" -Type Info
Write-StatusMessage "LUN: $nextLun" -Type Info

if ($WhatIf) {
    Write-StatusMessage "[WHAT-IF] Would create and attach data disk with the following parameters:" -Type Info
    Write-StatusMessage "  Disk Name: $diskName" -Type Info
    Write-StatusMessage "  Size: $DiskSizeGB GB" -Type Info
    Write-StatusMessage "  Storage Type: $StorageAccountType" -Type Info
    Write-StatusMessage "  LUN: $nextLun" -Type Info
    exit 0
}

try {
    # Create the managed disk
    Write-StatusMessage "Creating managed disk..." -Type Info
    az disk create `
        --name $diskName `
        --resource-group $ResourceGroupName `
        --location $vmLocation `
        --size-gb $DiskSizeGB `
        --sku $StorageAccountType

    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "Failed to create managed disk" -Type Error
        exit 1
    }

    Write-StatusMessage "Managed disk created successfully" -Type Success

    # Attach the disk to the VM
    Write-StatusMessage "Attaching disk to VM..." -Type Info
    az vm disk attach `
        --name $diskName `
        --resource-group $ResourceGroupName `
        --vm-name $VmName `
        --lun $nextLun

    if ($LASTEXITCODE -ne 0) {
        Write-StatusMessage "Failed to attach disk to VM" -Type Error
        Write-StatusMessage "You may need to clean up the created disk manually" -Type Warning
        exit 1
    }

    Write-StatusMessage "Disk attached successfully!" -Type Success

    # Get VM public IP for SSH instructions
    $publicIp = az vm show --name $VmName --resource-group $ResourceGroupName --show-details --query "publicIps" --output tsv

    Write-StatusMessage "" -Type Info
    Write-StatusMessage "=== Next Steps ===" -Type Info
    Write-StatusMessage "1. SSH to your VM:" -Type Info
    if ($publicIp) {
        Write-StatusMessage "   ssh azureuser@$publicIp" -Type Info
    } else {
        Write-StatusMessage "   ssh azureuser@<VM-PUBLIC-IP>" -Type Info
    }
    Write-StatusMessage "" -Type Info
    Write-StatusMessage "2. Run the data disk setup script:" -Type Info
    Write-StatusMessage "   sudo curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/add-vm-relay-data-disk.sh | sudo bash" -Type Info
    Write-StatusMessage "" -Type Info
    Write-StatusMessage "3. Verify the setup:" -Type Info
    Write-StatusMessage "   sudo /usr/local/bin/strfry-health-check.sh" -Type Info
    Write-StatusMessage "" -Type Info
    Write-StatusMessage "The data disk has been attached as LUN $nextLun and will be automatically configured by the setup script." -Type Success

} catch {
    Write-StatusMessage "Failed to attach data disk: $($_.Exception.Message)" -Type Error
    exit 1
}
