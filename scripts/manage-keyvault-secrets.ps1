# Manage Key Vault Secrets for Nostria Infrastructure
#
# This script helps you manage notification app secrets in Azure Key Vault.
# The secrets are read by the notification app at runtime via Key Vault references.

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "nostria-global",
    
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("set", "get", "list", "delete")]
    [string]$Action = "list",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("private-vapid-key", "notification-api-key", "both")]
    [string]$SecretName = "both",
    
    [Parameter(Mandatory=$false)]
    [SecureString]$SecretValue
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

# Find Key Vault if not provided
if (-not $KeyVaultName) {
    Write-StatusMessage "Finding Key Vault in resource group $ResourceGroupName..." -Type Info
    try {
        $keyVaults = Get-AzKeyVault -ResourceGroupName $ResourceGroupName | Where-Object { $_.VaultName -like "nostria-kv" }
        if ($keyVaults.Count -eq 0) {
            Write-StatusMessage "No Key Vault found with pattern 'nostria-kv-*' in resource group $ResourceGroupName" -Type Error
            Write-StatusMessage "Make sure you have deployed the infrastructure first with: .\deploy-main.ps1" -Type Info
            exit 1
        } elseif ($keyVaults.Count -gt 1) {
            Write-StatusMessage "Multiple Key Vaults found:" -Type Warning
            $keyVaults | ForEach-Object { Write-StatusMessage "  - $($_.VaultName)" -Type Info }
            Write-StatusMessage "Please specify the Key Vault name using -KeyVaultName parameter" -Type Error
            exit 1
        } else {
            $KeyVaultName = $keyVaults[0].VaultName
            Write-StatusMessage "Found Key Vault: $KeyVaultName" -Type Success
        }
    } catch {
        Write-StatusMessage "Failed to find Key Vault. Error: $_" -Type Error
        exit 1
    }
}

# Verify Key Vault exists and we have access
try {
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ErrorAction Stop
    Write-StatusMessage "Using Key Vault: $KeyVaultName" -Type Info
} catch {
    Write-StatusMessage "Failed to access Key Vault '$KeyVaultName'. Error: $_" -Type Error
    Write-StatusMessage "Make sure you have the required permissions and the Key Vault exists." -Type Warning
    exit 1
}

# Execute the requested action
switch ($Action) {
    "list" {
        Write-StatusMessage "Listing secrets in Key Vault '$KeyVaultName'..." -Type Info
        try {
            $secrets = Get-AzKeyVaultSecret -VaultName $KeyVaultName
            if ($secrets.Count -eq 0) {
                Write-StatusMessage "No secrets found in Key Vault." -Type Warning
                Write-StatusMessage "" -Type Info
                Write-StatusMessage "To add secrets, use:" -Type Info
                Write-StatusMessage "  .\manage-keyvault-secrets.ps1 -Action set -SecretName private-vapid-key" -Type Info
                Write-StatusMessage "  .\manage-keyvault-secrets.ps1 -Action set -SecretName notification-api-key" -Type Info
            } else {
                Write-StatusMessage "" -Type Info
                Write-StatusMessage "Secrets in Key Vault:" -Type Success
                $secrets | ForEach-Object {
                    $lastUpdated = if ($_.Updated) { $_.Updated.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
                    Write-StatusMessage "  - $($_.Name) (Updated: $lastUpdated)" -Type Info
                }
            }
        } catch {
            Write-StatusMessage "Failed to list secrets. Error: $_" -Type Error
        }
    }
    
    "get" {
        if ($SecretName -eq "both") {
            Write-StatusMessage "Getting both secrets from Key Vault '$KeyVaultName'..." -Type Info
            try {
                $privateKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "private-vapid-key" -AsPlainText -ErrorAction SilentlyContinue
                $apiKey = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name "notification-api-key" -AsPlainText -ErrorAction SilentlyContinue
                
                Write-StatusMessage "" -Type Info
                if ($privateKey) {
                    Write-StatusMessage "private-vapid-key: *** (Hidden for security)" -Type Success
                } else {
                    Write-StatusMessage "private-vapid-key: Not found" -Type Warning
                }
                
                if ($apiKey) {
                    Write-StatusMessage "notification-api-key: *** (Hidden for security)" -Type Success
                } else {
                    Write-StatusMessage "notification-api-key: Not found" -Type Warning
                }
            } catch {
                Write-StatusMessage "Failed to get secrets. Error: $_" -Type Error
            }
        } else {
            Write-StatusMessage "Getting secret '$SecretName' from Key Vault '$KeyVaultName'..." -Type Info
            try {
                $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -AsPlainText
                Write-StatusMessage "Secret found (value hidden for security)" -Type Success
            } catch {
                Write-StatusMessage "Failed to get secret '$SecretName'. Error: $_" -Type Error
            }
        }
    }
    
    "set" {
        if ($SecretName -eq "both") {
            Write-StatusMessage "Setting both secrets requires individual calls." -Type Warning
            Write-StatusMessage "Use: -SecretName private-vapid-key or -SecretName notification-api-key" -Type Info
            exit 1
        }
        
        if (-not $SecretValue) {
            $SecretValue = Read-Host "Enter value for secret '$SecretName'" -AsSecureString
        }
        
        Write-StatusMessage "Setting secret '$SecretName' in Key Vault '$KeyVaultName'..." -Type Info
        try {
            Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -SecretValue $SecretValue | Out-Null
            Write-StatusMessage "Secret '$SecretName' set successfully!" -Type Success
            Write-StatusMessage "The notification app will automatically use this secret value." -Type Info
        } catch {
            Write-StatusMessage "Failed to set secret '$SecretName'. Error: $_" -Type Error
        }
    }
    
    "delete" {
        if ($SecretName -eq "both") {
            Write-StatusMessage "Deleting both secrets..." -Type Warning
            $confirm = Read-Host "Are you sure you want to delete both secrets? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-StatusMessage "Operation cancelled." -Type Info
                exit 0
            }
            
            try {
                Remove-AzKeyVaultSecret -VaultName $KeyVaultName -Name "private-vapid-key" -Force
                Remove-AzKeyVaultSecret -VaultName $KeyVaultName -Name "notification-api-key" -Force
                Write-StatusMessage "Both secrets deleted successfully!" -Type Success
            } catch {
                Write-StatusMessage "Failed to delete secrets. Error: $_" -Type Error
            }
        } else {
            Write-StatusMessage "Deleting secret '$SecretName'..." -Type Warning
            $confirm = Read-Host "Are you sure you want to delete secret '$SecretName'? (y/N)"
            if ($confirm -ne 'y' -and $confirm -ne 'Y') {
                Write-StatusMessage "Operation cancelled." -Type Info
                exit 0
            }
            
            try {
                Remove-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName -Force
                Write-StatusMessage "Secret '$SecretName' deleted successfully!" -Type Success
            } catch {
                Write-StatusMessage "Failed to delete secret '$SecretName'. Error: $_" -Type Error
            }
        }
    }
}

Write-StatusMessage "" -Type Info
Write-StatusMessage "Key Vault secret management completed." -Type Success
