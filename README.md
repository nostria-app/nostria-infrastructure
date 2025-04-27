# Nostria Infrastructure

This repository contains infrastructure as code (IaC) for the Nostria Azure environment, using Bicep templates and PowerShell automation scripts.

## Infrastructure Components

- **Linux App Service Plan (B1)**: Hosts all container applications
- **Container Apps**:
  - `discovery.nostria.app`: Discovery service (single instance)
  - `relay[N].nostria.app`: Relay services (multiple instances as needed)
  - `media[N].nostria.app`: Media services (multiple instances as needed)
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
# Login to your Azure account
Connect-AzAccount

# Select your subscription if you have multiple
Set-AzContext -SubscriptionId "<your-subscription-id>"
```

## Deployment

### Deploying the Infrastructure

Use the `deploy.ps1` script to deploy the entire infrastructure:

```powershell
./scripts/deploy.ps1 -ResourceGroupName "nostria" -Location "westeurope"
```

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
  ./scripts/deploy.ps1 -ResourceGroupName "nostria" -StorageSku "Premium_LRS"
  ```

- Adding monitoring and alerting for the infrastructure
- Implementing Key Vault for secrets management
- Setting up traffic manager for load balancing


## Notes

- Web Apps have a principal with access to the storage account.
- Web apps does not have access to the backup storage account.
- This ensures that hacked web apps cannot access the backup storage account.

## License

See [LICENSE](./LICENSE) for details.
