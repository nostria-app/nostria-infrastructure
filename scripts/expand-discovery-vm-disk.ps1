[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("eu", "us", "af")]
    [string]$Region = "eu",
    
    [Parameter(Mandatory=$false)]
    [int]$NewSizeGB = 256,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

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

# Resource names
$resourceGroupName = "nostria-$Region-discovery"
$vmName = "nostria-$Region-discovery-vm"
$diskName = "$vmName-data-disk"

Write-StatusMessage "=== Expanding Discovery VM Data Disk ===" -Type Info
Write-StatusMessage "Region: $Region" -Type Info
Write-StatusMessage "Resource Group: $resourceGroupName" -Type Info
Write-StatusMessage "VM Name: $vmName" -Type Info
Write-StatusMessage "Disk Name: $diskName" -Type Info
Write-StatusMessage "New Size: $NewSizeGB GB" -Type Info

if ($WhatIf) {
    Write-StatusMessage "WhatIf mode - no changes will be made" -Type Warning
}

# Check current disk size
Write-StatusMessage "`nChecking current disk size..." -Type Info
$disk = az disk show --resource-group $resourceGroupName --name $diskName | ConvertFrom-Json
$currentSize = $disk.diskSizeGb

Write-StatusMessage "Current disk size: $currentSize GB" -Type Info

if ($currentSize -ge $NewSizeGB) {
    Write-StatusMessage "Disk is already $currentSize GB (>= requested $NewSizeGB GB). No expansion needed." -Type Warning
    exit 0
}

# Step 1: Stop the VM
Write-StatusMessage "`nStep 1: Stopping VM $vmName..." -Type Info
if (-not $WhatIf) {
    az vm stop --resource-group $resourceGroupName --name $vmName
    Write-StatusMessage "VM stopped" -Type Success
} else {
    Write-StatusMessage "Would stop VM" -Type Warning
}

# Step 2: Deallocate the VM (required to resize disk)
Write-StatusMessage "`nStep 2: Deallocating VM..." -Type Info
if (-not $WhatIf) {
    az vm deallocate --resource-group $resourceGroupName --name $vmName
    Write-StatusMessage "VM deallocated" -Type Success
} else {
    Write-StatusMessage "Would deallocate VM" -Type Warning
}

# Step 3: Resize the disk
Write-StatusMessage "`nStep 3: Resizing disk from $currentSize GB to $NewSizeGB GB..." -Type Info
if (-not $WhatIf) {
    az disk update --resource-group $resourceGroupName --name $diskName --size-gb $NewSizeGB
    Write-StatusMessage "Disk resized to $NewSizeGB GB" -Type Success
} else {
    Write-StatusMessage "Would resize disk to $NewSizeGB GB" -Type Warning
}

# Step 4: Start the VM
Write-StatusMessage "`nStep 4: Starting VM..." -Type Info
if (-not $WhatIf) {
    az vm start --resource-group $resourceGroupName --name $vmName
    Write-StatusMessage "VM started" -Type Success
} else {
    Write-StatusMessage "Would start VM" -Type Warning
}

Write-StatusMessage "`n=== Disk Expansion Complete ===" -Type Success
Write-StatusMessage @"

IMPORTANT: After the VM starts, SSH in and expand the filesystem:

ssh azureuser@$vmName.*.cloudapp.azure.com

Then run:
# Check current partition size
lsblk
df -h /var/lib/strfry

# Expand the partition (assuming /dev/sdc1)
sudo growpart /dev/sdc 1

# Expand the filesystem
sudo resize2fs /dev/sdc1

# Verify
df -h /var/lib/strfry

# Restart strfry
sudo systemctl restart strfry strfry-router
"@ -Type Info
