param(
  [Parameter(Mandatory=$true)]
  [string]$SourceStorageName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [string]$BackupStorageName = "nostriabak"
)

Write-Host "Backing up files from $SourceStorageName to $BackupStorageName..." -ForegroundColor Yellow

# Get storage account keys using Azure CLI
try {
    $sourceKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $SourceStorageName --query "[0].value" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Failed to get source storage account key" }
    
    $backupKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $BackupStorageName --query "[0].value" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Failed to get backup storage account key" }
} catch {
    Write-Host "Error retrieving storage account keys: $_" -ForegroundColor Red
    exit 1
}

# Get all shares from source storage
try {
    $sharesJson = (az storage share list --account-name $SourceStorageName --account-key $sourceKey -o json)
    if ($LASTEXITCODE -ne 0) { throw "Failed to list source shares" }
    
    $shares = $sharesJson | ConvertFrom-Json
    Write-Host "Found $($shares.Count) shares to backup." -ForegroundColor Green
} catch {
    Write-Host "Error retrieving shares: $_" -ForegroundColor Red
    exit 1
}

# Use a central 'backups' share in the backup storage account
$backupShareName = "backups"

# Check if backup share exists
$backupShareExists = (az storage share exists --name $backupShareName --account-name $BackupStorageName --account-key $backupKey --query "exists" -o tsv)
if ($backupShareExists -eq "false") {
    Write-Host "  Creating backup share: $backupShareName" -ForegroundColor Yellow
    az storage share create --name $backupShareName --account-name $BackupStorageName --account-key $backupKey | Out-Null
}

foreach ($share in $shares) {
    Write-Host "Processing share: $($share.name)" -ForegroundColor Cyan
    
    # Create a folder in the backup share for this storage account/share
    $backupFolderPath = "${SourceStorageName}/${$share.name}"
    
    # Create folder structure in backup if needed
    try {
        # Create storage account folder
        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $SourceStorageName | Out-Null
        # Create share folder
        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $backupFolderPath | Out-Null
    } catch {}
    
    # Create a temporary directory for copying files
    $tempDir = Join-Path $env:TEMP "AzureFileShareBackup_$(Get-Random)"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "  Using temp directory: $tempDir" -ForegroundColor Gray
    
    try {
        # Download files from source
        Write-Host "  Downloading files from source share..." -ForegroundColor Yellow
        # List all files in the source share recursively
        $filesJson = (az storage file list -s $share.name --account-name $SourceStorageName --account-key $sourceKey -p "/" --recursive -o json)
        $files = $filesJson | ConvertFrom-Json
        
        # Download each file
        foreach ($file in $files) {
            if ($file.type -eq "file") {
                $filePath = $file.name
                $localFilePath = Join-Path $tempDir $filePath
                
                # Create parent directory if it doesn't exist
                $parentDir = Split-Path -Path $localFilePath -Parent
                if (!(Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }
                
                # Download the file
                az storage file download --share-name $share.name --account-name $SourceStorageName --account-key $sourceKey --path $filePath --dest $localFilePath | Out-Null
            }
        }

        # Upload files to backup
        Write-Host "  Uploading files to backup share..." -ForegroundColor Yellow
        $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
        foreach ($localFile in $localFiles) {
            $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
            $backupPath = "$backupFolderPath/$relativePath"
            $directoryPath = Split-Path -Path $backupPath -Parent
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory in backup if needed
                try {
                    $dirExists = (az storage file exists --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $directoryPath --query "exists" -o tsv 2>$null)
                    if ($dirExists -eq "false" -or $LASTEXITCODE -ne 0) {
                        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $directoryPath | Out-Null
                    }
                } catch {}
            }
            
            # Upload file to backup
            az storage file upload --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --source $localFile.FullName --path $backupPath | Out-Null
        }
    } catch {
        Write-Host "  Error processing share $($share.name): $_" -ForegroundColor Red
    } finally {
        # Clean up the temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Backup completed successfully." -ForegroundColor Green