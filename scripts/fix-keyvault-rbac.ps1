# Fix Key Vault RBAC permissions for all Nostria web apps
# This script grants the "Key Vault Secrets User" role to all web apps that use Key Vault references

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$KeyVaultName = "nostria-kv",
    
    [Parameter(Mandatory=$false)]
    [string]$GlobalResourceGroupName = "nostria-global",
    
    [Parameter(Mandatory=$false)]
    [string[]]$RegionalResourceGroups = @("nostria-eu", "nostria-us", "nostria-af")
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

Write-StatusMessage "🔐 Fixing Key Vault RBAC permissions for Nostria web apps..." -Type Info

try {
    # Get the Key Vault
    $keyVault = Get-AzKeyVault -VaultName $KeyVaultName -ResourceGroupName $GlobalResourceGroupName -ErrorAction Stop
    Write-StatusMessage "Found Key Vault: $($keyVault.VaultName)" -Type Success
    
    if (-not $keyVault.EnableRbacAuthorization) {
        Write-StatusMessage "⚠️ Key Vault does not have RBAC authorization enabled. Using access policies instead." -Type Warning
        Write-StatusMessage "This script is designed for RBAC-enabled Key Vaults." -Type Warning
        exit 0
    }
    
    # Get all resource groups to check
    $allResourceGroups = @($GlobalResourceGroupName) + $RegionalResourceGroups
    $totalAppsProcessed = 0
    $totalRolesAssigned = 0
    
    foreach ($rgName in $allResourceGroups) {
        Write-StatusMessage "`nChecking resource group: $rgName" -Type Info
        
        try {
            # Get web apps that use Key Vault references
            $webApps = Get-AzWebApp -ResourceGroupName $rgName -ErrorAction SilentlyContinue | Where-Object {
                $_.SiteConfig.AppSettings | Where-Object {$_.Value -like "*@Microsoft.KeyVault*"}
            }
            
            if ($webApps) {
                Write-StatusMessage "Found $($webApps.Count) web app(s) with Key Vault references in $rgName" -Type Info
                
                foreach ($app in $webApps) {
                    $totalAppsProcessed++
                    $principalId = $app.Identity.PrincipalId
                    
                    if ($principalId) {
                        try {
                            # Check if role assignment already exists
                            $existingAssignment = Get-AzRoleAssignment -ObjectId $principalId -Scope $keyVault.ResourceId -RoleDefinitionName "Key Vault Secrets User" -ErrorAction SilentlyContinue
                            
                            if (-not $existingAssignment) {
                                Write-StatusMessage "  Granting Key Vault Secrets User role to $($app.Name)..." -Type Info
                                New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Key Vault Secrets User" -Scope $keyVault.ResourceId -ErrorAction Stop
                                Write-StatusMessage "  ✅ Role assigned to $($app.Name)" -Type Success
                                $totalRolesAssigned++
                            } else {
                                Write-StatusMessage "  ✅ Role already assigned to $($app.Name)" -Type Success
                            }
                        }
                        catch {
                            Write-StatusMessage "  ❌ Failed to assign role to $($app.Name): $($_.Exception.Message)" -Type Error
                        }
                    } else {
                        Write-StatusMessage "  ⚠️ No managed identity found for $($app.Name)" -Type Warning
                    }
                }
            } else {
                Write-StatusMessage "No web apps with Key Vault references found in $rgName" -Type Info
            }
        }
        catch {
            Write-StatusMessage "⚠️ Error accessing resource group ${rgName}: $($_.Exception.Message)" -Type Warning
        }
    }
    
    Write-StatusMessage "`n📊 Summary:" -Type Info
    Write-StatusMessage "Total apps processed: $totalAppsProcessed" -Type Info
    Write-StatusMessage "New roles assigned: $totalRolesAssigned" -Type Success
    
    if ($totalRolesAssigned -gt 0) {
        Write-StatusMessage "`n🔄 Recommendation: Restart affected web apps to ensure they pick up the new permissions:" -Type Info
        Write-StatusMessage "Get-AzWebApp | Where-Object {\$_.SiteConfig.AppSettings | Where-Object {\$_.Value -like '*@Microsoft.KeyVault*'}} | Restart-AzWebApp" -Type Info
    }
    
    Write-StatusMessage "`n✅ Key Vault RBAC permissions fix completed!" -Type Success
}
catch {
    Write-StatusMessage "❌ Error: $($_.Exception.Message)" -Type Error
    exit 1
}