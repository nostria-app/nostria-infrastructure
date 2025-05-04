param(
  [Parameter(Mandatory=$true)]
  [string]$WebAppName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [string]$BackupStorageName = "nostriabak",

  [Parameter(Mandatory=$false)]
  [string]$PathToRestore = "data",

  [Parameter(Mandatory=$false)]
  [string]$SubscriptionId = ""
)

Write-Host "Restoring files from $BackupStorageName to $WebAppName ($PathToRestore)..." -ForegroundColor Yellow

# Ensure we're logged in to Azure CLI and using the correct subscription
if ($SubscriptionId) {
    Write-Host "Setting subscription to $SubscriptionId..." -ForegroundColor Gray
    az account set --subscription $SubscriptionId
}

# Load necessary .NET assemblies for URL encoding/decoding
Add-Type -AssemblyName System.Web

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

# Set up storage operations with managed identity if possible
$useManagedIdentity = $false
try {
    # Check if we can get a token using managed identity
    $tokenTest = az account get-access-token --query "accessToken" -o tsv 2>$null
    if ($tokenTest -and (-not $LASTEXITCODE)) {
        # Verify that we have appropriate permissions on the storage account
        $testResult = az storage share exists --name "test-mi-access" --account-name $BackupStorageName --auth-mode login --output none 2>$null
        if ($LASTEXITCODE -eq 0) {
            $useManagedIdentity = $true
            Write-Host "Using managed identity for storage operations" -ForegroundColor Green
        } else {
            Write-Host "Managed identity is available but doesn't have necessary permissions on the storage account" -ForegroundColor Yellow
            Write-Host "Falling back to storage account key authentication" -ForegroundColor Yellow
        }
    }
} catch {
    Write-Host "Unable to use managed identity, falling back to account keys" -ForegroundColor Yellow
}

# Get storage account key if managed identity is not available
if (-not $useManagedIdentity) {
    try {
        $backupKey = (az storage account keys list --resource-group $ResourceGroupName --account-name $BackupStorageName --query "[0].value" -o tsv)
        if ($LASTEXITCODE -ne 0) { throw "Failed to get backup storage account key" }
    } catch {
        Write-Host "Error retrieving storage account key: $_" -ForegroundColor Red
        exit 1
    }
}

# The central backup share name
$backupShareName = "backups"

# Check if backup folder exists for the web app
$backupFolderPath = $WebAppName
Write-Host "Checking for backups under path: $backupFolderPath" -ForegroundColor Yellow

try {
    # First, list all directories in the share to see what's available
    Write-Host "Listing all directories in the backup share to verify structure..." -ForegroundColor Yellow
    if ($useManagedIdentity) {
        $allDirectories = az storage directory list --share-name $backupShareName --account-name $BackupStorageName --auth-mode login -o json | ConvertFrom-Json
    } else {
        $allDirectories = az storage directory list --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey -o json | ConvertFrom-Json
    }
    
    Write-Host "Found the following directories in the backup share:" -ForegroundColor Gray
    foreach ($dir in $allDirectories) {
        Write-Host "  $($dir.name)" -ForegroundColor Gray
    }

    # Now check specifically for our target folder
    if ($useManagedIdentity) {
        # Use managed identity authentication
        $folderExistsCommand = "az storage directory exists --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --name `"$backupFolderPath`" --query exists -o tsv"
        Write-Host "Running command: $folderExistsCommand" -ForegroundColor Gray
        $folderExists = (Invoke-Expression $folderExistsCommand 2>$null)
    } else {
        # Use storage key authentication
        $folderExistsCommand = "az storage directory exists --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name `"$backupFolderPath`" --query exists -o tsv"
        Write-Host "Running command: $folderExistsCommand" -ForegroundColor Gray
        $folderExists = (Invoke-Expression $folderExistsCommand 2>$null)
    }
    
    Write-Host "Directory exists check result: $folderExists (Exit code: $LASTEXITCODE)" -ForegroundColor Gray
    
    if ($folderExists -eq "false" -or $LASTEXITCODE -ne 0) {
        throw "No backup folder found for $WebAppName at path $backupFolderPath"
    }
    
    Write-Host "Found backup folder for $WebAppName" -ForegroundColor Green
} catch {
    Write-Host "Error retrieving backup folder: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}

# Create a temporary directory for copying files
$tempDir = Join-Path $env:TEMP "AzureWebAppRestore_$(Get-Random)"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
Write-Host "Using temp directory: $tempDir" -ForegroundColor Gray

try {
    # Download backup files from storage
    Write-Host "Downloading files from backup..." -ForegroundColor Yellow

    # Define paths for data folder under the webapp backup
    $dataFolderPath = "$backupFolderPath/data"
    Write-Host "Looking for data folder at path: $dataFolderPath" -ForegroundColor Yellow

    # Check for dedicated data folder
    Write-Host "Checking for dedicated data folder at $dataFolderPath..." -ForegroundColor Yellow
    $dataFolderExists = $false

    try {
        if ($useManagedIdentity) {
            $dataFolderCheck = az storage directory exists --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --name $dataFolderPath --query exists -o tsv 2>$null
            $dataFolderExists = $dataFolderCheck -eq "true"
        } else {
            $dataFolderCheck = az storage directory exists --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $dataFolderPath --query exists -o tsv 2>$null
            $dataFolderExists = $dataFolderCheck -eq "true"
        }
    } catch {
        Write-Host "Error checking data folder: $_" -ForegroundColor Red
        $dataFolderExists = $false
    }

    # Decide what to download
    if ($dataFolderExists) {
        Write-Host "Found dedicated data folder at $dataFolderPath, downloading from there" -ForegroundColor Green
        $downloadPath = $dataFolderPath
    } else {
        Write-Host "No dedicated data folder found, downloading from root backup folder $backupFolderPath" -ForegroundColor Yellow
        $downloadPath = $backupFolderPath
    }

    # Use az storage file download-batch for robust download of all files (including binaries)
    Write-Host "Downloading all files from Azure File Share path '$downloadPath' to local temp directory '$tempDir'..." -ForegroundColor Yellow
    $pattern = "$downloadPath/*"
    if ($useManagedIdentity) {
        $downloadResult = az storage file download-batch --source $backupShareName --account-name $BackupStorageName --auth-mode login --destination $tempDir --pattern $pattern 2>&1
    } else {
        $downloadResult = az storage file download-batch --source $backupShareName --account-name $BackupStorageName --account-key $backupKey --destination $tempDir --pattern $pattern 2>&1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error downloading files: $downloadResult" -ForegroundColor Red
        exit 1
    }

    # Check if files were downloaded
    $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
    $fileCount = $localFiles.Count

    if ($fileCount -eq 0) {
        Write-Host "No files were downloaded to restore. Check if the backup exists." -ForegroundColor Yellow
        Write-Host "Check the following: " -ForegroundColor Yellow
        Write-Host "1. The backup path $backupFolderPath in share $backupShareName" -ForegroundColor Yellow
        Write-Host "2. Permissions to access the storage account" -ForegroundColor Yellow
        Write-Host "3. Network connectivity to the storage account" -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "Successfully downloaded $fileCount files for restoration." -ForegroundColor Green
    }

    # Get publishing credentials and Kudu information for the web app
    Write-Host "Getting publishing credentials for web app..." -ForegroundColor Yellow
    $publishingProfile = az webapp deployment list-publishing-profiles --name $WebAppName --resource-group $ResourceGroupName | ConvertFrom-Json
    
    # Filter to get the MSDeploy profile
    $msDeployProfile = $publishingProfile | Where-Object { $_.publishMethod -eq "MSDeploy" }
    if (-not $msDeployProfile) {
        # Fallback to first profile if MSDeploy not found
        $msDeployProfile = $publishingProfile[0] 
        if (-not $msDeployProfile) {
            throw "No publishing profile found for web app $WebAppName"
        }
    }
    
    $kuduHost = $msDeployProfile.publishUrl
    $userName = $msDeployProfile.userName
    $password = $msDeployProfile.userPWD
    
    # Ensure we have a proper hostname - often the publishUrl looks like waws-prod-xyz.publish.azurewebsites.windows.net
    if (-not $kuduHost.Contains(".")) {
        # Try with the default format if not a full hostname
        $kuduHost = "$WebAppName.scm.azurewebsites.net"
        Write-Host "Using default SCM URL: $kuduHost" -ForegroundColor Yellow
    }

    # Don't include the port number in the hostname for Test-Connection
    if ($kuduHost.Contains(":")) {
        $testHost = $kuduHost.Split(":")[0]
    } else {
        $testHost = $kuduHost
    }

    # Test the connection to Kudu
    Write-Host "Testing connection to Kudu host: $testHost..." -ForegroundColor Yellow
    $testConnection = Test-Connection -ComputerName $testHost -Count 1 -Quiet
    if (-not $testConnection) {
        Write-Host "Cannot reach Kudu host. Trying alternate SCM URL format..." -ForegroundColor Yellow
        $kuduHost = "$WebAppName.scm.azurewebsites.net"
        $testHost = $kuduHost
        $testConnection = Test-Connection -ComputerName $testHost -Count 1 -Quiet
        if (-not $testConnection) {
            throw "Cannot connect to Kudu host at $kuduHost. Check if the web app exists and is running."
        }
    }
    
    Write-Host "Successfully connected to Kudu host: $kuduHost" -ForegroundColor Green

    # Base64 encode the credentials
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userName, $password)))
    $userAgent = "PowerShell Script"
    
    # Format the path correctly for the Kudu API
    # If PathToRestore is just "data", we need "/data" for Kudu API
    # If it already has a leading slash, use it as is
    if (-not $PathToRestore.StartsWith("/")) {
        $kuduPath = "/$PathToRestore"
    } else {
        $kuduPath = $PathToRestore
    }
    
    # Ensure path ends with slash for directory operations
    if (-not $kuduPath.EndsWith("/")) {
        $kuduPath = "$kuduPath/"
    }
    
    # Upload files to web app
    Write-Host "Uploading files to web app at path $kuduPath..." -ForegroundColor Yellow
    $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
    
    if ($localFiles.Count -eq 0) {
        Write-Host "No files were downloaded to restore. Check if the backup exists." -ForegroundColor Yellow
    } else {
        foreach ($localFile in $localFiles) {
            # Get the relative path from temp directory
            $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
            # Convert backslashes to forward slashes for web paths
            $relativePath = $relativePath.Replace("\", "/")
            
            # Process the relative path to handle the folder structure correctly
            if ($dataFolderExists) {
                # If we downloaded from a data subfolder, we need to strip that prefix
                # Example: if downloadPath was 'webapp/data', we remove that prefix
                $downloadPathPrefix = $downloadPath.TrimStart("/")
                if ($relativePath.StartsWith($downloadPathPrefix)) {
                    # +1 to account for the forward slash after the prefix
                    $relativePath = $relativePath.Substring($downloadPathPrefix.Length + 1)
                    Write-Host "  Adjusted path to: $relativePath" -ForegroundColor Gray
                }
            } else {
                # If we downloaded from the root backup folder, we need to strip the webapp name
                $webAppNamePrefix = $WebAppName
                if ($relativePath.StartsWith($webAppNamePrefix)) {
                    # +1 to account for the forward slash after the prefix
                    $relativePath = $relativePath.Substring($webAppNamePrefix.Length + 1)
                    Write-Host "  Adjusted path to: $relativePath" -ForegroundColor Gray
                }
                
                # If there's still a 'data' prefix in the path, we should handle that too
                if ($relativePath.StartsWith("data/")) {
                    $relativePath = $relativePath.Substring(5) # "data/".Length = 5
                    Write-Host "  Further adjusted path to: $relativePath" -ForegroundColor Gray
                }
            }
            
            # Target path in the web app
            $targetPath = "$kuduPath$relativePath"
            
            # Make sure the directory exists in the web app
            $targetDir = Split-Path -Path $targetPath -Parent
            if (-not $targetDir.EndsWith("/")) {
                $targetDir = "$targetDir/"
            }
            
            $dirUrl = "https://$kuduHost/api/vfs$targetDir"
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
                            try {
                                $null = Invoke-RestMethod -Uri $currentDirUrl -Headers $headers -Method Put
                            } catch {
                                Write-Host "  Error creating directory $currentPath`: $_" -ForegroundColor Red
                            }
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
                Write-Host "  Error uploading $relativePath`: $_" -ForegroundColor Red
                # Continue with other files
            }
            
            # Add small delay to avoid overwhelming the Kudu API
            Start-Sleep -Milliseconds 100
        }
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "If this is a permission issue, ensure you have the right level of access to the web app and storage account." -ForegroundColor Yellow
    exit 1
} finally {
    # Clean up the temp directory
    # Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Restore completed successfully." -ForegroundColor Green
Write-Host "Files have been restored from backup to $WebAppName at path $PathToRestore" -ForegroundColor Green
Write-Host "Note: You may need to restart the web app for changes to take effect." -ForegroundColor Yellow

if (-not $useManagedIdentity) {
    Write-Host "Note: This script used storage account keys for authentication." -ForegroundColor Yellow
    Write-Host "To use Managed Identity with RBAC instead (recommended):" -ForegroundColor Yellow
    Write-Host "1. Assign 'Storage File Data SMB Share Contributor' role to the identity running this script" -ForegroundColor Yellow
    Write-Host "2. Enable RBAC on the storage account" -ForegroundColor Yellow
}