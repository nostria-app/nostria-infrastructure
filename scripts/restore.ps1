param(
  [Parameter(Mandatory=$true)]
  [string]$TargetStorageName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [string]$BackupStorageName = "nostriabak"
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

# The central backup share name
$backupShareName = "backups"

# Check if backup folder exists for the target storage account
$backupFolderPrefix = "$TargetStorageName/"
Write-Host "Checking for backups under prefix: $backupFolderPrefix" -ForegroundColor Yellow

try {
    # List all directories in the backup share for the target storage account
    $directoriesJson = (az storage directory list --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path "$TargetStorageName" -o json)
    if ($LASTEXITCODE -ne 0) { throw "Failed to list backup folders or no backup folders found" }
    
    $directories = $directoriesJson | ConvertFrom-Json
    if ($directories.Count -eq 0) {
        Write-Host "No backup folders found for $TargetStorageName" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Found backup folders for $TargetStorageName" -ForegroundColor Green
} catch {
    Write-Host "Error retrieving backup folders: $_" -ForegroundColor Red
    exit 1
}

# Create a temporary directory for copying files
$tempDir = Join-Path $env:TEMP "AzureFileShareRestore_$(Get-Random)"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
Write-Host "Using temp directory: $tempDir" -ForegroundColor Gray

# For each share in the backup (subfolders under the target storage account folder)
foreach ($dir in $directories) {
    # Get share name from directory path
    $shareName = Split-Path -Path $dir.name -Leaf
    
    Write-Host "Processing backup for share: $shareName" -ForegroundColor Cyan
    
    # Check if target share exists
    $targetShareExists = (az storage share exists --name $shareName --account-name $TargetStorageName --account-key $targetKey --query "exists" -o tsv)
    if ($targetShareExists -eq "false") {
        Write-Host "  Creating target share: $shareName" -ForegroundColor Yellow
        az storage share create --name $shareName --account-name $TargetStorageName --account-key $targetKey | Out-Null
    }
    
    try {
        # Clear temp directory for this share
        Remove-Item -Path "$tempDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Download files from backup share
        Write-Host "  Downloading files from backup..." -ForegroundColor Yellow
        $backupFolderPath = "$TargetStorageName/$shareName"
        
        # List all files in the backup folder recursively
        $filesJson = (az storage file list -s $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $backupFolderPath --recursive -o json)
        $files = $filesJson | ConvertFrom-Json
        
        # Download each file
        foreach ($file in $files) {
            if ($file.type -eq "file") {
                # Get relative path removing the backup folder prefix
                $relativePath = $file.name.Substring($backupFolderPath.Length + 1)
                $localFilePath = Join-Path $tempDir $relativePath
                
                # Create parent directory if it doesn't exist
                $parentDir = Split-Path -Path $localFilePath -Parent
                if (!(Test-Path $parentDir)) {
                    New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
                }
                
                # Download the file
                az storage file download --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $file.name --dest $localFilePath | Out-Null
            }
        }
        
        # Upload files to target share
        Write-Host "  Uploading files to target share..." -ForegroundColor Yellow
        $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
        foreach ($localFile in $localFiles) {
            $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
            $directoryPath = Split-Path -Path $relativePath -Parent
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory in target if needed
                try {
                    $dirExists = (az storage file exists --share-name $shareName --account-name $TargetStorageName --account-key $targetKey --path $directoryPath --query "exists" -o tsv 2>$null)
                    if ($dirExists -eq "false" -or $LASTEXITCODE -ne 0) {
                        az storage directory create --share-name $shareName --account-name $TargetStorageName --account-key $targetKey --name $directoryPath | Out-Null
                    }
                } catch {}
            }
            
            # Upload file to target
            az storage file upload --share-name $shareName --account-name $TargetStorageName --account-key $targetKey --source $localFile.FullName --path $relativePath | Out-Null
        }
    } catch {
        Write-Host "  Error processing share $shareName: $_" -ForegroundColor Red
    }
}

# Clean up the temp directory
Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Restore completed successfully." -ForegroundColor Green