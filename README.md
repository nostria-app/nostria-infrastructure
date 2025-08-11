# Nostria Infrastructure

This repository contains infrastructure as code (IaC) for the Nostria Azure environment, using Bicep templates and PowerShell automation scripts.

## Infrastructure Components

- **Linux App Service Plan (B1)**: Hosts all container applications and function apps
- **Container Apps**:
  - `discovery.nostria.app`: Discovery service (single instance)
  - `relay[N].nostria.app`: Relay services (multiple instances as needed)
  - `media[N].nostria.app`: Media services (multiple instances as needed)
- **Function Apps**:
  - `proxy.[region].nostria.app`: Proxy function for regional traffic routing (one per region)
- **VM Relay Servers** (NEW):
  - `ribo.[region].nostria.app`: First dedicated VM relay with strfry and Caddy
  - `rilo.[region].nostria.app`: Second dedicated VM relay (when VmRelayCount > 1)
  - High-performance nostr relay on dedicated infrastructure
  - Automatic HTTPS/TLS certificate management
  - Deployed to resource group: `nostria-[region]-relays`
- **Storage Accounts**:
  - Each service has its own storage account with Azure File Share mounted to the container
  - Each storage account has a corresponding backup storage account

## Getting Started

### Prerequisites

- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps)
- Azure Subscription with appropriate permissions

### Login to Azure

```powershell
Install-Module -Name Az -AllowClobber -Scope CurrentUser

Import-Module Az

Get-Command Connect-AzAccount

# Login to your Azure account
Connect-AzAccount

# Select your subscription if you have multiple
Set-AzContext -SubscriptionId "<your-subscription-id>"
```

## Deployment

### Update Discovery Relays

When a new image of the Discovery Relay is built using the separate repo, run this command to update the web app:

```powershell
 ./scripts/update-web-app.ps1 -WebAppNames @("nostria-discovery-eu") -ResourceGroup "nostria-eu" -ContainerImage "ghcr.io/nostria-app/discovery-relay:9e75597ed5c7ad4e97f5278b35f325ded9465b43"
```

### Manage VM Relays

For VM-based relay management:

```bash
# SSH to the VM relay
ssh azureuser@<VM-PUBLIC-IP>

# Check relay status
/usr/local/bin/strfry-health-check.sh

# View service logs
sudo journalctl -u strfry -f
sudo journalctl -u caddy -f

# Restart services
sudo systemctl restart strfry
sudo systemctl restart caddy
```

### Deploying the Infrastructure

Use the deployment scripts to deploy the infrastructure:

```powershell
# Deploy main infrastructure
./scripts/deploy-main.ps1

# Deploy regional container-based services
./scripts/deploy-region.ps1 -Regions eu,us,af

# Deploy VM-based relay servers
./scripts/deploy-vm-relay.ps1 -Region "eu" -VmRelayCount 1

# Deploy VM-based discovery relay servers
./scripts/deploy-discovery-relay-vm.ps1 -Region "eu"
```

### Deploying Discovery Relay VM

After running the powershell script, the following must be done:

1. **Update DNS**: Point `discovery.[region].nostria.app` to your VM's public IP
2. **Wait for DNS propagation**: 5-30 minutes typically
3. **Enable HTTPS**: Run the HTTPS enable script

```sh
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/enable-https.sh | sudo bash
```

**If the HTTPS script hangs**: The script may hang at "Reloading Caddy with HTTPS configuration...". If it hangs for more than 2 minutes:

1. **Press `Ctrl+C`** to cancel the hanging script
2. **Run the simple emergency fix**:
   ```sh
   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/simple-https-fix.sh | sudo bash
   ```
3. **Verify HTTPS is working**: `curl -v https://discovery.[region].nostria.app/health`

**Alternative manual fix**:
```sh
# Stop any hanging processes
sudo pkill -f caddy; sudo systemctl stop caddy; sleep 3

# Restart Caddy manually
sudo systemctl start caddy

# Monitor certificate acquisition
sudo journalctl -u caddy -f
```

**Troubleshooting HTTPS issues**:
```sh
# Fix Caddy PKI/startup errors (if Caddy won't start)
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-caddy-pki-error.sh | sudo bash

# For persistent PKI or port binding errors, use the aggressive fix
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-caddy-aggressive.sh | sudo bash

# For port binding issues only (faster)
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-caddy-port-binding.sh | sudo bash

# Check DNS propagation status
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/check-dns-propagation.sh | sudo bash

# Check if DNS is properly configured (alternative)
nslookup discovery.[region].nostria.app

# Debug endpoint issues
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/debug-discovery-endpoints.sh | sudo bash

# Fix strfry monitoring if needed
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-discovery-endpoints.sh | sudo bash
```

=== IMPORTANT: Enable HTTPS after DNS configuration ===
This deployment uses HTTP to avoid certificate acquisition timeouts.
After you configure DNS records for discovery.af.nostria.app pointing to this VM's public IP:

1. Update DNS: Point discovery.af.nostria.app to VM-PUBLIC-IP
2. Wait for DNS propagation (5-30 minutes)  
3. Enable HTTPS by running: enable-https.sh

### VM Relay Deployment (NEW)

For high-performance dedicated relay servers:

```powershell
# Deploy a single VM relay in EU region
./scripts/deploy-vm-relay.ps1 -Region "eu"

# Deploy multiple VM relays with custom settings
./scripts/deploy-vm-relay.ps1 `
    -Region "eu" `
    -VmRelayCount 2 `
    -VmSize "Standard_D2s_v3"
```

**Features:**
- Dedicated Ubuntu VMs with strfry nostr relay
- Caddy reverse proxy with automatic HTTPS
- Domains follow naming pattern: `ribo.[region].nostria.app`, `rilo.[region].nostria.app`, etc.
- High-performance C++ implementation
- Built-in monitoring and health checks
- Resource group: `nostria-[region]-relays`

**Requirements:**
- SSH public key at `$env:USERPROFILE\.ssh\id_rsa.pub`
- DNS configuration for each relay domain
- Azure subscription with VM deployment permissions

Parameters:
- `ResourceGroupName`: Name of the resource group (default: "nostria")
- `Location`: Azure region (default: "westeurope")
- `RelayCount`: Number of relay instances to create (default: 1)
- `MediaCount`: Number of media instances to create (default: 1)

### Scaling the Infrastructure

To add more relay or media instances, simply update the count parameters:

```powershell
# Add two more relay instances (creating relay2 and relay3)
./scripts/deploy.ps1 -ResourceGroupName "nostria" -RelayCount 3

# Add more media instances
./scripts/deploy.ps1 -ResourceGroupName "nostria" -MediaCount 2
```

## Backup and Restore

```powershell
./scripts/backup.ps1 -WebAppName "nostria-discovery"
./scripts/restore.ps1 -WebAppName "nostria-discovery"
```

### Backing Up a Storage Account

```powershell
# Backup the media1 storage account
./scripts/backup.ps1 -SourceStorageName "nostriamedia1" -ResourceGroupName "nostria"
```

This will copy all files from the source storage account to the backup storage account (nostriamedia1bkp).

### Restoring from Backup

```powershell
# Restore from backup to the media1 storage account
./scripts/restore.ps1 -BackupStorageName "nostriamedia1bkp" -TargetStorageName "nostriamedia1" -ResourceGroupName "nostria"
```

## Nostria Notification

Make sure that the following environment variables are set in the container app:

- `PUBLIC_VAPID_KEY`: Public VAPID key for web push notifications
- `PRIVATE_VAPID_KEY`: Private VAPID key for web push notifications
- `VAPID_SUBJECT`: E-mail for the VAPID
- `NOTIFICATION_API_KEY`: Admin API key for the Nostria Notification service

## GitHub Actions Workflows

This repository includes GitHub Actions workflows for automating the deployment of containers:

- `deploy-discovery.yml`: Builds and deploys the discovery container app when changes are pushed to the `discovery/` directory.

### Setting up GitHub Actions

1. Add the following secrets to your GitHub repository:
   - `AZURE_CREDENTIALS`: JSON output from `az ad sp create-for-rbac` command

## Future Improvements

- Upgrading storage accounts to Premium tier:
  ```powershell
  # Update the sku parameter in the bicep template when deploying
  ./scripts/deploy.ps1 -ResourceGroupName "nostria-we" -StorageSku "Premium_LRS"
  ```

- Adding monitoring and alerting for the infrastructure
- Implementing Key Vault for secrets management
- Setting up traffic manager for load balancing


## Notes

- Web Apps have a principal with access to the storage account.
- Web apps does not have access to the backup storage account.
- This ensures that hacked web apps cannot access the backup storage account.

Consider Blob Index Tags: https://learn.microsoft.com/en-us/azure/storage/blobs/storage-manage-find-blobs

## Regional Abbreviations

https://www.jlaundry.nz/2022/azure_region_abbreviations/

## Regions

### Planned regions for Nostria

discovery-eu.nostria.app (Europe)   
discovery-us.nostria.app (USA)   
discovery-as.nostria.app (Asia)   
discovery-af.nostria.app (Africa)   
discovery-sa.nostria.app (South America)   
discovery-au.nostria.app (Australia)   
discovery-jp.nostria.app (Japan)   
discovery-cn.nostria.app (China)   
discovery-in.nostria.app (India)   
discovery-me.nostria.app (Middle East)   

We might need to expand with multiple data centers in the same region, perhaps we could either name them with a number (e.g. discovery-eu1.nostria.app, discovery-eu2.nostria.app) or use a different naming convention.

### Data centers for each region

eu: westeurope (Amsterdam, Netherlands)   
us: centralus (Iowa, US)   
as: southeastasia (Singapore)   
af: southafricanorth (Johannesburg, South Africa)   
sa: brazilsouth (São Paulo, Brazil)   
au: australiaeast (Sydney, Australia)   
jp: japaneast (Tokyo, Japan)   
cn: chinanorth (Beijing, China) (Special considerations for China, might not be available for us)   
in: centralindia (Pune, India)   
me: uaenorth (Abu Dhabi, UAE)   

### Initial Deployment Schedule Plan

1. Europe - This is our primary region, stateless apps will only be hosted here initially.
2. Africa - This is our first secondary region.
3. US - This is our second secondary region.
4. Asia, we will first deploy in Singapore, which gives OK coverage for the rest of Asia and Australia.
5. South America.

## Developer Notes

How to get the Azure credentials for GitHub Actions:

```powershell
# Get name and id and type:
az ad sp list | ConvertFrom-Json | Where-Object { $_.servicePrincipalType -ne "Application" } | Select-Object displayName, appId, id, servicePrincipalType | Format-Table -AutoSize | Out-File -FilePath './filtered-service-principals.txt'

# Get all details:
az ad sp list | ConvertFrom-Json | Where-Object { $_.servicePrincipalType -ne "Application" } | Out-File -FilePath './filtered-service-principals-all.txt'
```

```powershell	
# Create a service principal with the required permissions
az ad sp create-for-rbac --name "nostria-deployment" --role contributor --scopes /subscriptions/<your-subscription-id> --sdk-auth > ./github-actions-credentials.json
```

After a lot of issues with mapping volumes to the container, it was discovered that it's not really needed. As long as the apps within the container can take configurations from environment variables, we can set that to /home/data which is then mapped in the setup.

Instead of overriding the volume mapping in the container, we can also map the default paths to the Azure File Share.

nostria-media: /app/data
nostria-status: /app/data
nostria-discovery: app/data
nostria-relay: /app/strfry-db and /etc/strfry.conf

### TODO:

https://azure.github.io/AppService/2025/04/01/Docker-compose-migration.html


## License

See [LICENSE](./LICENSE) for details.
