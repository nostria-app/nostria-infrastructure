param(
  [Parameter(Mandatory=$true)]
  [string]$BackupStorageName,
  
  [Parameter(Mandatory=$true)]
  [string]$TargetStorageName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria"
)

Write-Host "Restoring files from $BackupStorageName to $TargetStorageName..." -ForegroundColor Yellow

# Get storage account keys using Azure CLI
try {
    $backupKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $BackupStorageName --query "[0].value" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Failed to get backup storage account key" }
    
    $targetKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $TargetStorageName --query "[0].value" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Failed to get target storage account key" }
} catch {
    Write-Host "Error retrieving storage account keys: $_" -ForegroundColor Red
    exit 1
}

# Get all backup shares
try {
    $backupSharesJson = (az storage share list --account-name $BackupStorageName --account-key $backupKey --query "[?contains(name, '-backup')]" -o json)
    if ($LASTEXITCODE -ne 0) { throw "Failed to list backup shares" }
    
    $backupShares = $backupSharesJson | ConvertFrom-Json
    Write-Host "Found $($backupShares.Count) backup shares to restore." -ForegroundColor Green
} catch {
    Write-Host "Error retrieving backup shares: $_" -ForegroundColor Red
    exit 1
}

foreach ($backupShare in $backupShares) {
    # Create target share if it doesn't exist
    $targetShareName = $backupShare.name -replace "-backup", ""
    Write-Host "Processing backup share: $($backupShare.name) -> $targetShareName" -ForegroundColor Cyan
    
    # Check if target share exists
    $targetShareExists = (az storage share exists --name $targetShareName --account-name $TargetStorageName --account-key $targetKey --query "exists" -o tsv)
    if ($targetShareExists -eq "false") {
        Write-Host "  Creating target share: $targetShareName" -ForegroundColor Yellow
        az storage share create --name $targetShareName --account-name $TargetStorageName --account-key $targetKey | Out-Null
    }
    
    # Create a temporary directory for copying files
    $tempDir = Join-Path $env:TEMP "AzureFileShareRestore_$(Get-Random)"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "  Using temp directory: $tempDir" -ForegroundColor Gray
    
    try {
        # Download files from backup share
        Write-Host "  Downloading files from backup share..." -ForegroundColor Yellow
        # List all files in the backup share recursively
        $filesJson = (az storage file list -s $backupShare.name --account-name $BackupStorageName --account-key $backupKey -p "/" --recursive -o json)
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
                az storage file download --share-name $backupShare.name --account-name $BackupStorageName --account-key $backupKey --path $filePath --dest $localFilePath | Out-Null
            }
        }

        # Upload files to target
        Write-Host "  Uploading files to target share..." -ForegroundColor Yellow
        $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
        foreach ($localFile in $localFiles) {
            $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
            $directoryPath = Split-Path -Path $relativePath -Parent
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory in target if needed
                try {
                    $dirExists = (az storage file exists --share-name $targetShareName --account-name $TargetStorageName --account-key $targetKey --path $directoryPath --query "exists" -o tsv 2>$null)
                    if ($dirExists -eq "false" -or $LASTEXITCODE -ne 0) {
                        az storage directory create --share-name $targetShareName --account-name $TargetStorageName --account-key $targetKey --name $directoryPath | Out-Null
                    }
                } catch {}
            }
            
            # Upload file to target
            az storage file upload --share-name $targetShareName --account-name $TargetStorageName --account-key $targetKey --source $localFile.FullName --path $relativePath | Out-Null
        }
    } catch {
        Write-Host "  Error processing share $($backupShare.name): $_" -ForegroundColor Red
    } finally {
        # Clean up the temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Restore completed successfully." -ForegroundColor Green