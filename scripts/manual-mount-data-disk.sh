#!/bin/bash
# Manual script to check and mount the data disk for strfry database

echo "=== Manual Data Disk Mount Script ==="
echo "Date: $(date)"

# Check current disk status
echo ""
echo "1. Current disk layout:"
lsblk -f

echo ""
echo "2. Current mount points:"
df -h

echo ""
echo "3. Available unmounted disks:"
lsblk -f | grep -v "MOUNTPOINT" | grep -v "/" | grep -v "SWAP"

echo ""
echo "4. Checking for Azure data disk..."

# Find the data disk - typically sdc on Azure VMs (sda=OS, sdb=temp disk, sdc=first data disk)
if [ -b "/dev/sdc" ]; then
    DATA_DISK="sdc"
    echo "Found potential data disk: /dev/$DATA_DISK"
elif [ -b "/dev/sdd" ]; then
    DATA_DISK="sdd"
    echo "Found potential data disk: /dev/$DATA_DISK"
else
    echo "No additional data disk found. Available disks:"
    lsblk -d -o NAME,SIZE,TYPE
    exit 1
fi

echo ""
echo "5. Checking disk /dev/$DATA_DISK:"
lsblk /dev/$DATA_DISK

# Check if it has partitions
PARTITION_COUNT=$(lsblk -n /dev/$DATA_DISK | wc -l)
if [ $PARTITION_COUNT -gt 1 ]; then
    PARTITION="${DATA_DISK}1"
    echo "Disk has partitions, using /dev/$PARTITION"
else
    echo "Disk has no partitions, will create one"
    
    # Create partition
    echo "Creating partition on /dev/$DATA_DISK..."
    parted /dev/$DATA_DISK --script mklabel gpt
    parted /dev/$DATA_DISK --script mkpart primary ext4 0% 100%
    
    # Wait for partition to be recognized
    sleep 2
    partprobe /dev/$DATA_DISK
    sleep 2
    
    PARTITION="${DATA_DISK}1"
fi

echo ""
echo "6. Checking partition /dev/$PARTITION:"
if [ ! -b "/dev/$PARTITION" ]; then
    echo "ERROR: Partition /dev/$PARTITION not found"
    exit 1
fi

# Check if partition has a filesystem
FILESYSTEM=$(blkid -o value -s TYPE /dev/$PARTITION 2>/dev/null)
if [ -z "$FILESYSTEM" ]; then
    echo "No filesystem found, formatting with ext4..."
    mkfs.ext4 -F /dev/$PARTITION
else
    echo "Filesystem found: $FILESYSTEM"
fi

echo ""
echo "7. Mounting the disk:"

# Create mount point if it doesn't exist
mkdir -p /var/lib/strfry

# Check if already mounted
if mount | grep -q "/var/lib/strfry"; then
    echo "Directory already mounted:"
    mount | grep "/var/lib/strfry"
else
    echo "Mounting /dev/$PARTITION to /var/lib/strfry..."
    mount /dev/$PARTITION /var/lib/strfry
    
    if [ $? -eq 0 ]; then
        echo "Successfully mounted!"
    else
        echo "ERROR: Failed to mount"
        exit 1
    fi
fi

echo ""
echo "8. Adding to /etc/fstab for permanent mounting:"
UUID=$(blkid -s UUID -o value /dev/$PARTITION)
echo "Disk UUID: $UUID"

# Remove any existing entry for /var/lib/strfry
sed -i '\|/var/lib/strfry|d' /etc/fstab

# Add new entry
echo "UUID=$UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab
echo "Added to /etc/fstab"

echo ""
echo "9. Setting up directory structure:"
mkdir -p /var/lib/strfry/db
chown -R strfry:strfry /var/lib/strfry 2>/dev/null || echo "strfry user doesn't exist yet, will set ownership later"

echo ""
echo "10. Final status:"
df -h /var/lib/strfry
ls -la /var/lib/strfry/

echo ""
echo "=== Mount completed successfully! ==="
echo "You can now run the discovery VM setup script, or restart the strfry service if it's already installed."
