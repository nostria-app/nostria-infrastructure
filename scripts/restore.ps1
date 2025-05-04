param(
  [Parameter(Mandatory=$true)]
  [string]$WebAppName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [string]$BackupStorageName = "nostriabak",

  [Parameter(Mandatory=$false)]
  [string]$PathToRestore = "/home/data",

  [Parameter(Mandatory=$false)]
  [string]$SubscriptionId = ""
)

Write-Host "Restoring files from $BackupStorageName to $WebAppName ($PathToRestore)..." -ForegroundColor Yellow

# Ensure we're logged in to Azure CLI and using the correct subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription to $SubscriptionId..." -ForegroundColor Gray
    az account set --subscription $SubscriptionId
}

# Validate if the web app exists
try {
    $webAppExists = az webapp show --name $WebAppName --resource-group $ResourceGroupName --query "name" -o tsv
    if (-not $webAppExists) {
        throw "Web app $WebAppName not found in resource group $ResourceGroupName"
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Validate if the backup storage account exists
try {
    $storageExists = az storage account show --name $BackupStorageName --resource-group $ResourceGroupName --query "name" -o tsv
    if (-not $storageExists) {
        throw "Backup storage account $BackupStorageName not found in resource group $ResourceGroupName"
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

# Get storage account key for the backup operation
# Note: In production, consider using managed identity and role assignments
try {
    $backupKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $BackupStorageName --query "[0].value" -o tsv)
    if ($LASTEXITCODE -ne 0) { throw "Failed to get backup storage account key" }
} catch {
    Write-Host "Error retrieving storage account key: $_" -ForegroundColor Red
    exit 1
}

# The central backup share name
$backupShareName = "backups"

# Check if backup folder exists for the web app
$backupFolderPath = $WebAppName
Write-Host "Checking for backups under path: $backupFolderPath" -ForegroundColor Yellow

try {
    # Check if the folder exists in the backup share
    $folderExists = (az storage file exists --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $backupFolderPath --query "exists" -o tsv)
    if ($folderExists -eq "false") {
        throw "No backup folder found for $WebAppName"
    }
    
    Write-Host "Found backup folder for $WebAppName" -ForegroundColor Green
} catch {
    Write-Host "Error retrieving backup folder: $_" -ForegroundColor Red
    exit 1
}

# Create a temporary directory for copying files
$tempDir = Join-Path $env:TEMP "AzureWebAppRestore_$(Get-Random)"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
Write-Host "Using temp directory: $tempDir" -ForegroundColor Gray

try {
    # Download backup files from storage
    Write-Host "Downloading files from backup..." -ForegroundColor Yellow
    
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
            Write-Host "  Downloading: $relativePath" -ForegroundColor Gray
            az storage file download --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $file.name --dest $localFilePath | Out-Null
        }
    }
    
    # Get publishing credentials for the web app
    $publishingInfo = az webapp deployment list-publishing-profiles --name $WebAppName --resource-group $ResourceGroupName --query "[?publishMethod=='MSDeploy'].[publishUrl,userName,userPWD]" -o json | ConvertFrom-Json
    $kuduHost = $publishingInfo[0][0]
    $username = $publishingInfo[0][1]
    $password = $publishingInfo[0][2]

    # Base64 encode the credentials
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))
    $userAgent = "PowerShell Script"
    
    # Create base directory in web app if it doesn't exist
    Write-Host "Ensuring target directory exists..." -ForegroundColor Yellow
    $basePathParts = $PathToRestore -split '/'
    $currentPath = ""
    
    # Skip the first empty part if path starts with /
    $startIndex = if ($basePathParts[0] -eq "") { 1 } else { 0 }
    
    for ($i = $startIndex; $i -lt $basePathParts.Length; $i++) {
        if ($basePathParts[$i]) {
            $currentPath += "/$($basePathParts[$i])"
            
            $dirUrl = "https://$kuduHost/api/vfs$currentPath"
            $headers = @{
                "Authorization" = "Basic $base64AuthInfo"
                "If-Match" = "*"
                "User-Agent" = $userAgent
                "Accept" = "application/json"
            }
            
            # Try to access the directory to see if it exists
            try {
                $null = Invoke-RestMethod -Uri "$dirUrl/" -Headers $headers -Method Get -ErrorAction SilentlyContinue
            } catch {
                # Directory doesn't exist, create it
                Write-Host "  Creating directory: $currentPath" -ForegroundColor Gray
                $null = Invoke-RestMethod -Uri "$dirUrl/" -Headers $headers -Method Put
            }
        }
    }
    
    # Upload files to web app
    Write-Host "Uploading files to web app..." -ForegroundColor Yellow
    $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
    foreach ($localFile in $localFiles) {
        # Get the relative path from temp directory
        $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
        # Convert backslashes to forward slashes for web paths
        $relativePath = $relativePath.Replace("\", "/")
        
        # Target path in the web app
        $targetPath = "$PathToRestore/$relativePath"
        
        # Create the directory if it doesn't exist
        $targetDir = Split-Path -Path $targetPath -Parent
        $dirUrl = "https://$kuduHost/api/vfs$targetDir/"
        $headers = @{
            "Authorization" = "Basic $base64AuthInfo"
            "If-Match" = "*"
            "User-Agent" = $userAgent
            "Accept" = "application/json"
        }
        
        # Check if directory exists and create if needed
        try {
            $null = Invoke-RestMethod -Uri $dirUrl -Headers $headers -Method Get -ErrorAction SilentlyContinue
        } catch {
            # Create directory hierarchy
            $pathSegments = $targetDir.TrimStart("/").Split("/")
            $currentPath = ""
            foreach ($segment in $pathSegments) {
                if ($segment) {
                    $currentPath += "/$segment"
                    $currentDirUrl = "https://$kuduHost/api/vfs$currentPath/"
                    
                    try {
                        $null = Invoke-RestMethod -Uri $currentDirUrl -Headers $headers -Method Get -ErrorAction SilentlyContinue
                    } catch {
                        Write-Host "  Creating directory: $currentPath" -ForegroundColor Gray
                        $null = Invoke-RestMethod -Uri $currentDirUrl -Headers $headers -Method Put
                    }
                }
            }
        }
        
        # Upload the file content
        $fileUrl = "https://$kuduHost/api/vfs$targetPath"
        $fileContent = [System.IO.File]::ReadAllBytes($localFile.FullName)
        
        # Set up file upload headers
        $fileHeaders = @{
            "Authorization" = "Basic $base64AuthInfo"
            "If-Match" = "*"
            "User-Agent" = $userAgent
            "Content-Type" = "application/octet-stream"
        }
        
        Write-Host "  Uploading: $relativePath" -ForegroundColor Gray
        
        try {
            $null = Invoke-RestMethod -Uri $fileUrl -Headers $fileHeaders -Method Put -Body $fileContent
        } catch {
            Write-Host "  Error uploading $relativePath: $_" -ForegroundColor Red
        }
        
        # Add small delay to avoid overwhelming the Kudu API
        Start-Sleep -Milliseconds 50
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
} finally {
    # Clean up the temp directory
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Restore completed successfully." -ForegroundColor Green
Write-Host "Files have been restored from backup to $WebAppName at path $PathToRestore" -ForegroundColor Green
Write-Host "Note: You may need to restart the web app for changes to take effect." -ForegroundColor Yellow