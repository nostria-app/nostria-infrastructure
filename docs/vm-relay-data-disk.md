# VM Relay Setup with Data Disk

This document describes the updated VM relay deployment that now includes a dedicated 32GB data disk for the strfry database, similar to the discovery relay but with a smaller disk size.

## Overview

The VM relay deployment has been enhanced with:
- **OS Disk**: 30GB Premium SSD (for operating system and applications)
- **Data Disk**: 32GB Standard SSD (dedicated for strfry LMDB database)
- **Automatic Disk Configuration**: Data disk is automatically partitioned, formatted, and mounted during setup
- **Proper Permissions**: Database directory ownership configured for strfry user

## Architecture Changes

### Before (Single Disk)
```
VM Relay
├── OS Disk (30GB Premium SSD)
    ├── / (root filesystem)
    ├── /var/lib/strfry/db (database on same disk)
    └── /var/log/strfry (logs)
```

### After (Dual Disk)
```
VM Relay
├── OS Disk (30GB Premium SSD)
│   ├── / (root filesystem)
│   └── /var/log/strfry (logs)
└── Data Disk (32GB Standard SSD)
    └── /var/lib/strfry (mounted here)
        └── db/ (strfry database)
```

## Benefits

1. **Performance Isolation**: Database I/O doesn't compete with OS operations
2. **Storage Optimization**: Uses Standard SSD for database (cost-effective) vs Premium SSD for OS (performance)
3. **Scalability**: Data disk can be expanded independently without affecting OS
4. **Backup Flexibility**: Can snapshot/backup database disk separately
5. **Consistent Architecture**: Matches discovery relay setup pattern

## Deployment

### Deploy New VM Relays

```powershell
# Deploy VM relays with data disk
.\scripts\deploy-vm-relay.ps1 -resourceGroupName "nostria-eu-relays" -location "West Europe" -region "eu" -vmRelayCount 1
```

### Verify Data Disk Setup

After deployment, SSH into the VM and verify:

```bash
# Check disk layout
lsblk

# Should show something like:
# NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
# sda       8:0    0   30G  0 disk 
# ├─sda1    8:1    0 29.9G  0 part /
# └─sda15   8:15   0  106M  0 part /boot/efi
# sdb       8:16   0   32G  0 disk 
# └─sdb1    8:17   0   32G  0 part /var/lib/strfry

# Check mount points
df -h /var/lib/strfry

# Check database directory permissions
ls -la /var/lib/strfry/
ls -la /var/lib/strfry/db/

# Run health check
sudo /usr/local/bin/strfry-health-check.sh
```

## Troubleshooting

### Data Disk Not Mounted

If the data disk isn't mounted properly:

```bash
# Check available disks
sudo lsblk -f

# Check if partition exists
sudo fdisk -l

# Manual mount (temporary)
sudo mkdir -p /var/lib/strfry
sudo mount /dev/sdb1 /var/lib/strfry

# Fix permanent mounting
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb1) /var/lib/strfry ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
```

### Permission Issues

If strfry has permission errors accessing the database:

```bash
# Run the fix script
sudo curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-vm-relay-permissions.sh | sudo bash

# Or manually fix permissions
sudo systemctl stop strfry
sudo chown -R strfry:strfry /var/lib/strfry
sudo chmod -R 755 /var/lib/strfry
sudo systemctl start strfry
```

### Database Corruption

If the database becomes corrupted:

```bash
# Stop strfry
sudo systemctl stop strfry

# Backup existing database
sudo cp -r /var/lib/strfry/db /var/lib/strfry/db.backup

# Remove corrupted database
sudo rm -rf /var/lib/strfry/db/*

# Reinitialize database
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=0 >/dev/null 2>&1

# Start strfry
sudo systemctl start strfry
```

## Monitoring

### Health Check

The updated health check script monitors:

```bash
#!/bin/bash
# Check strfry process and ports
# Check Caddy service and HTTPS
# Check database disk usage
# Verify data disk mount status

sudo /usr/local/bin/strfry-health-check.sh
```

### Disk Usage Monitoring

```bash
# Check database disk usage
df -h /var/lib/strfry

# Check if database is on separate disk
df /var/lib/strfry | tail -1
df / | tail -1

# Monitor disk I/O
iostat -x 1 5  # Requires sysstat package
```

## Backup and Recovery

### Database Backup

```bash
# Export database to backup file
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --fried > /backup/relay-backup-$(date +%Y%m%d).jsonl

# Verify backup size
ls -lh /backup/relay-backup-*.jsonl
```

### Data Disk Snapshot

```bash
# Azure CLI - Create disk snapshot
az snapshot create \
  --resource-group nostria-eu-relays \
  --source /subscriptions/{subscription-id}/resourceGroups/nostria-eu-relays/providers/Microsoft.Compute/disks/nostria-eu-ribo-vm-data-disk \
  --name nostria-eu-ribo-data-backup-$(date +%Y%m%d)
```

### Recovery

```bash
# Stop strfry service
sudo systemctl stop strfry

# Clear existing database
sudo rm -rf /var/lib/strfry/db/*

# Import from backup
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf import --fried < /backup/relay-backup-20241207.jsonl

# Start service
sudo systemctl start strfry
```

## Migration from Single-Disk Setup

If you have existing VM relays without data disks:

### 1. Add Data Disk via Azure Portal

1. Stop the VM
2. Add a new 32GB Standard SSD disk
3. Start the VM

### 2. Configure Data Disk

```bash
# SSH into the VM
ssh azureuser@your-vm-ip

# Stop strfry service
sudo systemctl stop strfry

# Backup existing database
sudo cp -r /var/lib/strfry /var/lib/strfry.backup

# Partition and format new disk
sudo fdisk /dev/sdb  # Create new partition
sudo mkfs.ext4 /dev/sdb1

# Mount new disk temporarily
sudo mkdir -p /mnt/newdisk
sudo mount /dev/sdb1 /mnt/newdisk

# Copy database to new disk
sudo cp -a /var/lib/strfry/* /mnt/newdisk/

# Update fstab for permanent mount
echo "UUID=$(sudo blkid -s UUID -o value /dev/sdb1) /var/lib/strfry ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Unmount temp and remount to final location
sudo umount /mnt/newdisk
sudo rm -rf /var/lib/strfry/*
sudo mount /dev/sdb1 /var/lib/strfry

# Fix permissions
sudo chown -R strfry:strfry /var/lib/strfry
sudo chmod -R 755 /var/lib/strfry

# Start strfry
sudo systemctl start strfry
```

## Performance Considerations

### Disk Performance

- **OS Disk (Premium SSD)**: ~5,000 IOPS, optimized for OS and application performance
- **Data Disk (Standard SSD)**: ~500 IOPS, suitable for LMDB database workloads
- **Network**: Up to 32 Mbps network performance on Standard_B2s

### LMDB Configuration

The strfry configuration optimizes for the data disk:

```hocon
dbParams {
    # Optimized for 32GB data disk
    mapsize = 34359738368  # 32GB
    maxreaders = 256
    noReadAhead = false    # Good performance on SSD
}
```

### Monitoring Queries

```bash
# Database size on disk
du -sh /var/lib/strfry/db/

# Number of events in database
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan '{}' | wc -l

# Database disk performance
sudo iotop -d 1  # Monitor disk I/O per process
```

## Cost Implications

### Storage Costs (West Europe example)

- **OS Disk**: 30GB Premium SSD ≈ €4.6/month
- **Data Disk**: 32GB Standard SSD ≈ €1.3/month
- **Total Storage**: ≈ €5.9/month (vs €4.6 single disk)

Additional €1.3/month for improved performance, reliability, and scalability.

### When to Expand Data Disk

Monitor and expand when:
- Database usage > 80% (check with `df -h /var/lib/strfry`)
- Performance degradation due to disk space
- Need to increase retention period

```bash
# Azure CLI - Expand data disk
az disk update --resource-group nostria-eu-relays --name nostria-eu-ribo-vm-data-disk --size-gb 64

# Then expand filesystem in VM
sudo growpart /dev/sdb 1
sudo resize2fs /dev/sdb1
```
