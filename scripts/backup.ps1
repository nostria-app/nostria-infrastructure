param(
  [Parameter(Mandatory=$true)]
  [string]$SourceStorageName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria"
)

# Add -BackupStorageName parameter if you want to specify a custom backup storage account
$BackupStorageName = "${SourceStorageName}bkp"

Write-Host "Backing up files from $SourceStorageName to $BackupStorageName..." -ForegroundColor Yellow

# Get storage account keys
try {
    $sourceKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $SourceStorageName -ErrorAction Stop)[0].Value
    $backupKey = (Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $BackupStorageName -ErrorAction Stop)[0].Value
} catch {
    Write-Host "Error retrieving storage account keys: $_" -ForegroundColor Red
    exit 1
}

# Create storage contexts
$sourceContext = New-AzStorageContext -StorageAccountName $SourceStorageName -StorageAccountKey $sourceKey
$backupContext = New-AzStorageContext -StorageAccountName $BackupStorageName -StorageAccountKey $backupKey

# Get all shares from source storage
try {
    $shares = Get-AzStorageShare -Context $sourceContext -ErrorAction Stop
    Write-Host "Found $($shares.Count) shares to backup." -ForegroundColor Green
} catch {
    Write-Host "Error retrieving shares: $_" -ForegroundColor Red
    exit 1
}

foreach ($share in $shares) {
    Write-Host "Processing share: $($share.Name)" -ForegroundColor Cyan
    
    # Create backup share if it doesn't exist
    $backupShareName = "$($share.Name)-backup"
    $backupShare = Get-AzStorageShare -Name $backupShareName -Context $backupContext -ErrorAction SilentlyContinue
    if (!$backupShare) {
        Write-Host "  Creating backup share: $backupShareName" -ForegroundColor Yellow
        New-AzStorageShare -Name $backupShareName -Context $backupContext | Out-Null
    }
    
    # Create a temporary directory for copying files
    $tempDir = Join-Path $env:TEMP "AzureFileShareBackup_$(Get-Random)"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    Write-Host "  Using temp directory: $tempDir" -ForegroundColor Gray
    
    try {
        # Download files from source
        Write-Host "  Downloading files from source share..." -ForegroundColor Yellow
        Get-AzStorageFile -Share $share -Path "/" | Get-AzStorageFileContent -Destination $tempDir -Force -Recurse

        # Upload files to backup
        Write-Host "  Uploading files to backup share..." -ForegroundColor Yellow
        $files = Get-ChildItem -Path $tempDir -Recurse -File
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($tempDir.Length + 1)
            $directoryPath = Split-Path -Path $relativePath -Parent
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory in backup if needed
                try {
                    $backupDir = Get-AzStorageFile -Share (Get-AzStorageShare -Name $backupShareName -Context $backupContext) -Path $directoryPath -ErrorAction SilentlyContinue
                    if (!$backupDir) {
                        New-AzStorageDirectory -Share (Get-AzStorageShare -Name $backupShareName -Context $backupContext) -Path $directoryPath | Out-Null
                    }
                } catch {}
            }
            
            # Upload file to backup
            Set-AzStorageFileContent -Share (Get-AzStorageShare -Name $backupShareName -Context $backupContext) -Source $file.FullName -Path $relativePath -Force | Out-Null
        }
    } catch {
        Write-Host "  Error processing share $($share.Name): $_" -ForegroundColor Red
    } finally {
        # Clean up the temp directory
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Backup completed successfully." -ForegroundColor Green