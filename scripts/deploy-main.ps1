[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$ParameterFilePath = "..\bicep\main.bicepparam",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName = "nostria-global",
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westeurope",
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf,

    [Parameter(Mandatory=$false)]
    [SecureString]$PostgreSQLAdminPassword,

    [Parameter(Mandatory=$false)]
    [switch]$DeployPostgreSQL,

    [Parameter(Mandatory=$false)]
    [SecureString]$BlossomAdminPassword
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

# Get the script's directory to use as reference for resolving paths
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $scriptDir

function Ensure-BicepInstalled {
    $bicepInPath = $null
    try { $bicepInPath = Get-Command bicep -ErrorAction SilentlyContinue } catch {}
    if (-not $bicepInPath) {
        Write-StatusMessage "Bicep not found in PATH. Installing Bicep..." -Type Warning
        $installPath = "$env:USERPROFILE\.bicep"
        $installDir = New-Item -ItemType Directory -Path $installPath -Force
        $bicepPath = "$installPath\bicep.exe"
        Write-StatusMessage "Downloading Bicep installer..." -Type Info
        $bicepUrl = "https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe"
        $webClient = New-Object System.Net.WebClient
        try {
            $webClient.DownloadFile($bicepUrl, $bicepPath)
            Write-StatusMessage "Bicep downloaded successfully." -Type Success
            $env:PATH += ";$installPath"
            Write-StatusMessage "Added Bicep to PATH for current session." -Type Success
            try {
                $bicepVersion = & $bicepPath --version
                Write-StatusMessage "Bicep installed successfully. Version: $bicepVersion" -Type Success
            } catch {
                Write-StatusMessage "Failed to run Bicep after installation. Error: $_" -Type Error
                throw "Failed to install Bicep properly"
            }
        } catch {
            Write-StatusMessage "Failed to download Bicep. Error: $_" -Type Error
            throw "Failed to download Bicep installer"
        }
    } else {
        try {
            $bicepVersion = & bicep --version
            Write-StatusMessage "Bicep is already installed. Version: $bicepVersion" -Type Info
        } catch {
            Write-StatusMessage "Bicep is installed but there was an error running it. Error: $_" -Type Warning
        }
    }
}

try { Ensure-BicepInstalled } catch {
    Write-StatusMessage "Failed to ensure Bicep is installed. Error: $_" -Type Error
    Write-StatusMessage "Please install Bicep manually from https://aka.ms/bicep-install" -Type Error
    exit 1
}

# Resolve template and parameter file paths using absolute paths
$bicepTemplate = Join-Path -Path $repoRoot -ChildPath "bicep\main.bicep" 
$bicepParamFile = Join-Path -Path $repoRoot -ChildPath $ParameterFilePath.TrimStart('.\').TrimStart('..')

# Verify that template files exist
if (-not (Test-Path -Path $bicepTemplate)) {
    Write-StatusMessage "Bicep template file not found at: $bicepTemplate" -Type Error
    exit 1
}

if (-not (Test-Path -Path $bicepParamFile)) {
    Write-StatusMessage "Parameter file not found at: $bicepParamFile" -Type Error
    exit 1
}

Write-StatusMessage "Using Bicep template: $bicepTemplate" -Type Info
Write-StatusMessage "Using parameter file: $bicepParamFile" -Type Info
Write-StatusMessage "Note: Secrets will be read from Key Vault. Ensure secrets are manually added to Key Vault after deployment." -Type Warning
Write-StatusMessage "Use -DeployPostgreSQL switch to include PostgreSQL server and related resources in the deployment." -Type Info

# Create the resource group if it doesn't exist
try {
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (-not $rg) {
        Write-StatusMessage "Creating resource group $ResourceGroupName in $Location..." -Type Info
        New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop
        Write-StatusMessage "Resource group $ResourceGroupName created successfully." -Type Success
    } else {
        Write-StatusMessage "Resource group $ResourceGroupName already exists." -Type Info
    }
} catch {
    Write-StatusMessage "Failed to create or check resource group $ResourceGroupName. Error: $_" -Type Error
    Write-StatusMessage "Make sure you're logged into Azure with the correct subscription." -Type Warning
    exit 1
}

# Deploy the Bicep template
if ($WhatIf) {
    Write-StatusMessage "Validating deployment for global infrastructure (what-if)..." -Type Info    try {
        $whatIfParams = @{
            ResourceGroupName = $ResourceGroupName
            TemplateFile = $bicepTemplate
            TemplateParameterFile = $bicepParamFile
            WhatIf = $true
            ErrorAction = 'Stop'
        }
        
        Write-StatusMessage "Using parameters: $(ConvertTo-Json ($whatIfParams.Keys) -Compress)" -Type Info
        $whatIfResult = New-AzResourceGroupDeployment @whatIfParams
        Write-StatusMessage "What-If validation completed successfully." -Type Success
    } catch {
        Write-StatusMessage "What-If validation failed. Error: $_" -Type Error
        exit 1
    }
} else {
    Write-StatusMessage "Starting deployment of global infrastructure to $ResourceGroupName..." -Type Info
    try {
        # Validate the template first
        if ($Debug) {
            Write-StatusMessage "Performing template validation before deployment..." -Type Info
            try {
                $validateParams = @{
                    ResourceGroupName = $ResourceGroupName
                    TemplateFile = $bicepTemplate
                    TemplateParameterFile = $bicepParamFile
                }
                Test-AzResourceGroupDeployment @validateParams
                Write-StatusMessage "Template validation successful." -Type Success
            }
            catch {
                Write-StatusMessage "Template validation failed with the following errors:" -Type Error
                Write-StatusMessage $_.Exception.Message -Type Error
                if ($_.Exception.InnerException) {
                    Write-StatusMessage "Inner error: $($_.Exception.InnerException.Message)" -Type Error
                }
                exit 1
            }
        }        
        
        # Prepare deployment parameters
        $deploymentParams = @{
            ResourceGroupName = $ResourceGroupName
            TemplateFile = $bicepTemplate
            ErrorAction = 'Stop'
            # Add deployment name for easier tracking
            Name = "MainDeployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            # Base parameters
            baseAppName = 'nostria'
        }
        
        # Determine if PostgreSQL should be deployed
        $shouldDeployPostgreSQL = $DeployPostgreSQL.IsPresent
        
        # If PostgreSQL deployment is requested, validate password is provided
        if ($shouldDeployPostgreSQL) {
            if (-not $PostgreSQLAdminPassword) {
                Write-StatusMessage "PostgreSQL deployment requested but no password provided. Please provide -PostgreSQLAdminPassword parameter." -Type Error
                exit 1
            }
            $deploymentParams['deployPostgreSQL'] = $true
            $deploymentParams['postgresqlAdminPassword'] = $PostgreSQLAdminPassword
            Write-StatusMessage "PostgreSQL deployment enabled with provided password." -Type Info
            Write-StatusMessage "Using template file directly to support additional parameters." -Type Info
        } else {
            # Check if password was provided without the deployment flag
            if ($PostgreSQLAdminPassword) {
                Write-StatusMessage "PostgreSQL password provided but deployment not requested. Use -DeployPostgreSQL to enable PostgreSQL deployment." -Type Warning
            }
            
            $deploymentParams['deployPostgreSQL'] = $false
            Write-StatusMessage "PostgreSQL deployment disabled. Use -DeployPostgreSQL to enable PostgreSQL resources." -Type Info
        }

        # Add Blossom admin password if provided
        if ($BlossomAdminPassword) {
            $deploymentParams['blossomAdminPassword'] = $BlossomAdminPassword
            Write-StatusMessage "Blossom admin password provided and will be stored in Key Vault." -Type Info
        } else {
            Write-StatusMessage "No Blossom admin password provided. Media servers will generate random passwords." -Type Warning
        }
        
        # Determine whether to use parameter file
        $useParameterFile = -not $shouldDeployPostgreSQL -and -not $BlossomAdminPassword
        if ($useParameterFile) {
            $deploymentParams['TemplateParameterFile'] = $bicepParamFile
            Write-StatusMessage "Using parameter file for deployment." -Type Info
        } else {
            Write-StatusMessage "Using template file directly with custom parameters." -Type Info
        }
        
        if ($Debug) {
            $deploymentParams['DeploymentDebugLogLevel'] = "All"
        }
        
        $deployment = New-AzResourceGroupDeployment @deploymentParams
        if ($deployment.ProvisioningState -eq "Succeeded") {
            Write-StatusMessage "Global infrastructure deployment succeeded!" -Type Success
        } else {
            Write-StatusMessage "Global infrastructure deployment failed. Status: $($deployment.ProvisioningState)" -Type Error
            exit 1
        }
    } catch {
        Write-StatusMessage "Failed to deploy global infrastructure. Error: $_" -Type Error
        
        # Extract detailed error information
        Write-StatusMessage "Attempting to extract detailed error information..." -Type Warning
        
        try {
            if ($_.Exception.Message -match "tracking id is '([^']+)'") {
                $trackingId = $matches[1]
                Write-StatusMessage "Deployment tracking ID: $trackingId" -Type Info
            }

            # Try to parse error details from exception message
            if ($_.Exception.Message -like "*See inner errors for details*") {
                Write-StatusMessage "Extracting inner error details:" -Type Warning
                
                # Get detailed error information
                $errorDetails = $null
                $errorRecord = $_
                
                # Attempt to get inner exception details
                if ($errorRecord.Exception.InnerException) {
                    Write-StatusMessage "Inner Exception: $($errorRecord.Exception.InnerException.Message)" -Type Error
                }
                
                # Try to get error details from response content if available
                if ($errorRecord.Exception.PSObject.Properties.Name -contains 'Response') {
                    $response = $errorRecord.Exception.Response
                    if ($response) {
                        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                        $reader.BaseStream.Position = 0
                        $reader.DiscardBufferedData()
                        $responseBody = $reader.ReadToEnd()
                        if ($responseBody) {
                            Write-StatusMessage "Response Body:" -Type Error
                            Write-StatusMessage $responseBody -Type Error
                        }
                    }
                }
            }
        } catch {
            Write-StatusMessage "Failed to extract detailed error information. Original error remains." -Type Warning
        }
        
        # Suggest troubleshooting steps
        Write-StatusMessage "`nTroubleshooting suggestions:" -Type Info
        Write-StatusMessage "1. Check if your main.bicep file has any syntax errors" -Type Info
        Write-StatusMessage "2. Verify all required parameters are provided in $bicepParamFile" -Type Info
        Write-StatusMessage "3. Check Azure subscription permissions" -Type Info
        Write-StatusMessage "4. Run the script again with -Debug to get more detailed logs" -Type Info
        Write-StatusMessage "5. Try a test deployment with only essential resources to isolate the issue" -Type Info
        
        exit 1
    }
}

# Post-deployment: Ensure RBAC roles are assigned for Key Vault access
if ($BlossomAdminPassword) {
    Write-StatusMessage "`nConfiguring Key Vault RBAC permissions..." -Type Info
    
    try {
        # Get the Key Vault
        $keyVault = Get-AzKeyVault -VaultName "nostria-kv" -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        
        if ($keyVault) {
            # Check if Key Vault uses RBAC authorization
            if ($keyVault.EnableRbacAuthorization) {
                Write-StatusMessage "Key Vault uses RBAC authorization. Ensuring all apps have proper access..." -Type Info
                
                # Get all web apps in this resource group that might need Key Vault access
                $webApps = Get-AzWebApp -ResourceGroupName $ResourceGroupName | Where-Object {
                    $_.SiteConfig.AppSettings | Where-Object {$_.Value -like "*@Microsoft.KeyVault*"}
                }
                
                foreach ($app in $webApps) {
                    $principalId = $app.Identity.PrincipalId
                    if ($principalId) {
                        try {
                            # Check if role assignment already exists
                            $existingAssignment = Get-AzRoleAssignment -ObjectId $principalId -Scope $keyVault.ResourceId -RoleDefinitionName "Key Vault Secrets User" -ErrorAction SilentlyContinue
                            
                            if (-not $existingAssignment) {
                                Write-StatusMessage "Granting Key Vault Secrets User role to $($app.Name)..." -Type Info
                                New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Key Vault Secrets User" -Scope $keyVault.ResourceId -ErrorAction Stop
                                Write-StatusMessage "✅ Role assigned to $($app.Name)" -Type Success
                            } else {
                                Write-StatusMessage "✅ Role already assigned to $($app.Name)" -Type Success
                            }
                        }
                        catch {
                            Write-StatusMessage "⚠️ Failed to assign role to $($app.Name): $($_.Exception.Message)" -Type Warning
                        }
                    }
                }
            } else {
                Write-StatusMessage "Key Vault uses access policies (RBAC not enabled)" -Type Info
            }
        } else {
            Write-StatusMessage "⚠️ Key Vault 'nostria-kv' not found in resource group $ResourceGroupName" -Type Warning
        }
    }
    catch {
        Write-StatusMessage "⚠️ Error configuring Key Vault RBAC: $($_.Exception.Message)" -Type Warning
    }
}

Write-StatusMessage "`nDeployment process completed!" -Type Success