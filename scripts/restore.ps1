param(
  [Parameter(Mandatory=$true)]
  [string]$BackupStorageName,
  
  [Parameter(Mandatory=$true)]
  [string]$TargetStorageName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria"
)

Write-Host "Restoring files from $BackupStorageName to $TargetStorageName..." -ForegroundColor Yellow

# Get storage account keys
try {
    $backupKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $BackupStorageName -ErrorAction Stop)[0].Value
    $targetKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $TargetStorageName -ErrorAction Stop)[0].Value
} catch {
    Write-Host "Error retrieving storage account keys: $_" -ForegroundColor Red
    exit 1
}

# Create storage contexts
$backupContext = New-AzStorageContext -StorageAccountName $BackupStorageName -StorageAccountKey $backupKey
$targetContext = New-AzStorageContext -StorageAccountName $TargetStorageName -StorageAccountKey $targetKey

# Get all backup shares
try {
    $backupShares = Get-AzStorageShare -Context $backupContext -ErrorAction Stop | Where-Object { $_.Name -like "*-backup" }
    Write-Host "Found $($backupShares.Count) backup shares to restore." -ForegroundColor Green
} catch {
    Write-Host "Error retrieving backup shares: $_" -ForegroundColor Red
    exit 1
}

foreach ($backupShare in $backupShares) {
    # Create target share if it doesn't exist
    $targetShareName = $backupShare.Name -replace "-backup", ""
    Write-Host "Processing backup share: $($backupShare.Name) -> $targetShareName" -ForegroundColor Cyan
    
    $targetShare = Get-AzStorageShare -Name $targetShareName -Context $targetContext -ErrorAction SilentlyContinue
    if (!$targetShare) {
        Write-Host "  Creating target share: $targetShareName" -ForegroundColor Yellow
        $targetShare = New-AzStorageShare -Name $targetShareName -Context $targetContext
    }
    
    # Create a temporary directory for copying files
    $tempDir = Join-Path $env:TEMP "AzureFileShareRestore_$(Get-Random)"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "  Using temp directory: $tempDir" -ForegroundColor Gray
    
    try {
        # Download files from backup
        Write-Host "  Downloading files from backup share..." -ForegroundColor Yellow
        Get-AzStorageFile -Share $backupShare -Path "/" | Get-AzStorageFileContent -Destination $tempDir -Force -Recurse

        # Upload files to target
        Write-Host "  Uploading files to target share..." -ForegroundColor Yellow
        $files = Get-ChildItem -Path $tempDir -Recurse -File
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($tempDir.Length + 1)
            $directoryPath = Split-Path -Path $relativePath -Parent
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory in target if needed
                try {
                    $targetDir = Get-AzStorageFile -Share (Get-AzStorageShare -Name $targetShareName -Context $targetContext) -Path $directoryPath -ErrorAction SilentlyContinue
                    if (!$targetDir) {
                        New-AzStorageDirectory -Share (Get-AzStorageShare -Name $targetShareName -Context $targetContext) -Path $directoryPath | Out-Null
                    }
                } catch {}
            }
            
            # Upload file to target
            Set-AzStorageFileContent -Share (Get-AzStorageShare -Name $targetShareName -Context $targetContext) -Source $file.FullName -Path $relativePath -Force | Out-Null
        }
    } catch {
        Write-Host "  Error processing share $($backupShare.Name): $_" -ForegroundColor Red
    } finally {
        # Clean up the temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Restore completed successfully." -ForegroundColor Green