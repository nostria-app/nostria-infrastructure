param(
  [Parameter(Mandatory=$true)]
  [string]$WebAppName,
  
  [Parameter(Mandatory=$false)]
  [string]$ResourceGroupName = "nostria",
  
  [Parameter(Mandatory=$false)]
  [string]$BackupStorageName = "nostriabak",

  [Parameter(Mandatory=$false)]
  [string]$PathToBackup = "data",

  [Parameter(Mandatory=$false)]
  [string]$SubscriptionId = ""
)

Write-Host "Backing up files from $WebAppName ($PathToBackup) to $BackupStorageName..." -ForegroundColor Yellow

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

# Check if backup share exists and create if needed
try {
    if ($useManagedIdentity) {
        # Use managed identity authentication
        $backupShareExists = (az storage share exists --name $backupShareName --account-name $BackupStorageName --auth-mode login --query "exists" -o tsv)
    } else {
        # Use storage key authentication
        $backupShareExists = (az storage share exists --name $backupShareName --account-name $BackupStorageName --account-key $backupKey --query "exists" -o tsv)
    }
    
    if ($backupShareExists -eq "false") {
        Write-Host "Creating backup share: $backupShareName" -ForegroundColor Yellow
        if ($useManagedIdentity) {
            az storage share create --name $backupShareName --account-name $BackupStorageName --auth-mode login | Out-Null
        } else {
            az storage share create --name $backupShareName --account-name $BackupStorageName --account-key $backupKey | Out-Null
        }
    }
} catch {
    Write-Host "Error checking/creating backup share: $_" -ForegroundColor Red
    exit 1
}

# Create a folder in the backup share for this web app
$backupFolderPath = $WebAppName
try {
    # Create webapp folder
    if ($useManagedIdentity) {
        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --name $backupFolderPath | Out-Null
    } else {
        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $backupFolderPath | Out-Null
    }
} catch {}

# Create a temporary directory for copying files
$tempDir = Join-Path $env:TEMP "AzureWebAppBackup_$(Get-Random)"
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
Write-Host "Using temp directory: $tempDir" -ForegroundColor Gray

try {
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
    # If PathToBackup is just "data", we need "/data" for Kudu API
    # If it already has a leading slash, use it as is
    if (-not $PathToBackup.StartsWith("/")) {
        $kuduPath = "/$PathToBackup"
    } else {
        $kuduPath = $PathToBackup
    }
    
    # Ensure path ends with slash for directory listing
    if (-not $kuduPath.EndsWith("/")) {
        $kuduPath = "$kuduPath/"
    }
    
    $apiUrl = "https://$kuduHost/api/vfs$kuduPath"
    
    Write-Host "Accessing Kudu API at: $apiUrl" -ForegroundColor Yellow

    # List files recursively using Kudu API
    Write-Host "Listing files from web app $WebAppName at path $kuduPath..." -ForegroundColor Yellow
    
    # Create a queue for BFS traversal
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($apiUrl)
    
    # Track visited directories to avoid cycles
    $visited = @{}
    $visited[$apiUrl] = $true
    
    # Keep track of all files found
    $allFiles = @()
    
    while ($queue.Count -gt 0) {
        $currentUrl = $queue.Dequeue()
        
        $headers = @{
            "Authorization" = "Basic $base64AuthInfo"
            "If-Match" = "*"
            "User-Agent" = $userAgent
            "Accept" = "application/json"
        }
        
        # Get the list of files/directories at the current path
        try {
            Write-Host "  Accessing: $currentUrl" -ForegroundColor Gray
            $response = Invoke-RestMethod -Uri $currentUrl -Headers $headers -Method Get -ErrorAction Stop
            
            foreach ($item in $response) {
                if ($item.mime -eq "inode/directory") {
                    # It's a directory, add to the queue if not visited
                    $dirName = [System.Web.HttpUtility]::UrlEncode($item.name)
                    $dirUrl = "$currentUrl$dirName/"
                    if (-not $visited.ContainsKey($dirUrl)) {
                        $queue.Enqueue($dirUrl)
                        $visited[$dirUrl] = $true
                    }
                } else {
                    # It's a file, add to our list
                    $allFiles += $item
                }
            }
        } catch {
            Write-Host "Error accessing $currentUrl`: $_" -ForegroundColor Red
            # Continue with other directories
        }
    }
    
    Write-Host "Found $($allFiles.Count) files to backup." -ForegroundColor Green
    
     # Process each file
     foreach ($file in $allFiles) {
        # Debug: Show raw file path from Kudu API
        Write-Host "  Debug - Raw file path: $($file.path)" -ForegroundColor DarkGray
        
        # Create the relative path by removing the kuduPath prefix
        $filePath = $file.path
        
        # Fix: Create the correct file URL by removing '/home' from the path if it exists
        if ($filePath.StartsWith("/home/")) {
            # Remove the '/home' prefix to get the correct API path
            $apiPath = $filePath.Substring(5) # Remove "/home"
            $fileUrl = "https://$kuduHost/api/vfs/$apiPath"
        } else {
            # Use the original path if it doesn't start with '/home'
            $fileUrl = "https://$kuduHost/api/vfs$filePath"
        }
        
        # Create relative path for local storage by removing leading directory if it exists
        # This handles cases where Kudu API returns paths with /home/
        $relativePath = $filePath.Substring($kuduPath.Length)
        if ($relativePath.StartsWith("home/")) {
            $relativePath = $relativePath.Substring(5) # Remove "home/"
        }
        
        # Log the relative path being processed
        Write-Host "  Processing relative path: $relativePath" -ForegroundColor DarkGray
        
        $localFilePath = Join-Path $tempDir $relativePath
        
        # Create parent directory if it doesn't exist
        $parentDir = Split-Path -Path $localFilePath -Parent
        if (!(Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        
        # Download the file using the Kudu API
        $fileHeaders = @{
            "Authorization" = "Basic $base64AuthInfo"
            "User-Agent" = $userAgent
        }
        
        Write-Host "  Downloading: $relativePath" -ForegroundColor Gray
        try {
            Write-Host "  Using URL: $fileUrl" -ForegroundColor DarkGray
            Invoke-RestMethod -Uri $fileUrl -Headers $fileHeaders -Method Get -OutFile $localFilePath -ErrorAction Stop
        } catch {
            Write-Host "  Error downloading $relativePath`: $_" -ForegroundColor Red
            # Continue with other files
        }
        
        # Add small delay to avoid overwhelming the Kudu API
        Start-Sleep -Milliseconds 100
    }
    
    # Upload files to backup
    Write-Host "Uploading files to backup share..." -ForegroundColor Yellow
    $localFiles = Get-ChildItem -Path $tempDir -Recurse -File
    
    if ($localFiles.Count -eq 0) {
        Write-Host "No files were downloaded to back up. Check if the path $kuduPath exists in the web app." -ForegroundColor Yellow
    } else {
        foreach ($localFile in $localFiles) {
            $relativePath = $localFile.FullName.Substring($tempDir.Length + 1)
            $backupPath = "$backupFolderPath/$relativePath"
            $directoryPath = Split-Path -Path $backupPath -Parent
            
            # Log the relative path and backup path
            Write-Host "  File: $relativePath -> $backupPath" -ForegroundColor DarkGray
            
            if (![string]::IsNullOrEmpty($directoryPath)) {
                # Create directory structure in backup if needed
                Write-Host "  Creating directory if needed: $directoryPath" -ForegroundColor DarkGray
                try {
                    # Check if the directory exists first to avoid unnecessary commands
                    if ($useManagedIdentity) {
                        $dirExists = (az storage file exists --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --path $directoryPath --query "exists" -o tsv 2>$null)
                    } else {
                        $dirExists = (az storage file exists --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --path $directoryPath --query "exists" -o tsv 2>$null)
                    }
                    
                    if ($dirExists -eq "false" -or $LASTEXITCODE -ne 0) {
                        # Create directory hierarchy recursively
                        $pathSegments = $directoryPath.Split('/')
                        $currentPath = ""
                        
                        foreach ($segment in $pathSegments) {
                            if (-not [string]::IsNullOrEmpty($segment)) {
                                if (-not [string]::IsNullOrEmpty($currentPath)) {
                                    $currentPath = "$currentPath/$segment"
                                } else {
                                    $currentPath = $segment
                                }
                                
                                Write-Host "    Creating directory segment: $currentPath" -ForegroundColor DarkGray
                                try {
                                    # Create each segment of the path
                                    if ($useManagedIdentity) {
                                        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --name $currentPath | Out-Null
                                    } else {
                                        az storage directory create --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --name $currentPath | Out-Null
                                    }
                                } catch {
                                    # Ignore errors if directory already exists
                                }
                            }
                        }
                    }
                } catch {}
            }
            
            # Upload file to backup
            Write-Host "  Uploading: $relativePath" -ForegroundColor Gray
            try {
                if ($useManagedIdentity) {
                    az storage file upload --share-name $backupShareName --account-name $BackupStorageName --auth-mode login --source $localFile.FullName --path $backupPath | Out-Null
                } else {
                    az storage file upload --share-name $backupShareName --account-name $BackupStorageName --account-key $backupKey --source $localFile.FullName --path $backupPath | Out-Null
                }
            } catch {
                Write-Host "  Error uploading $relativePath`: $_" -ForegroundColor Red
            }
        }
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Write-Host "If this is a permission issue, ensure you have the right level of access to the web app." -ForegroundColor Yellow
    exit 1
} finally {
    # Clean up the temp directory
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Backup completed successfully." -ForegroundColor Green
Write-Host "The backup has been stored in the '$backupShareName' share in storage account '$BackupStorageName' under folder '$WebAppName'." -ForegroundColor Green

if (-not $useManagedIdentity) {
    Write-Host "Note: This script used storage account keys for authentication." -ForegroundColor Yellow
    Write-Host "To use Managed Identity with RBAC instead (recommended):" -ForegroundColor Yellow
    Write-Host "1. Assign 'Storage File Data SMB Share Contributor' role to the identity running this script" -ForegroundColor Yellow
    Write-Host "2. Enable RBAC on the storage account" -ForegroundColor Yellow
}