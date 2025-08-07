#!/bin/bash
# Quick script to manually mount the data disk for strfry

echo "=== Manual Data Disk Mount for Strfry ==="
echo "Timestamp: $(date)"

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

echo "Step 1: Current disk and mount status"
echo "Available disks:"
lsblk -f

echo -e "\nCurrent mounts:"
df -h | grep -E "(Filesystem|/var/lib/strfry|/$)"

# Find the root disk
ROOT_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's|/dev/||')
echo -e "\nRoot disk: $ROOT_DISK"

# Find data disk
DATA_DISK=$(lsblk -dn -o NAME,TYPE | grep "disk" | grep -v "$ROOT_DISK" | head -n1 | awk '{print $1}')

if [ -z "$DATA_DISK" ]; then
    echo "ERROR: No data disk found!"
    echo "Please attach a data disk in Azure Portal first."
    exit 1
fi

echo "Data disk found: $DATA_DISK"

# Check if data disk has partitions
PARTITIONS=$(lsblk -n /dev/$DATA_DISK | tail -n +2)
if [ -z "$PARTITIONS" ]; then
    echo -e "\nData disk has no partitions. Creating partition..."
    
    # Stop strfry service
    systemctl stop strfry 2>/dev/null || true
    
    # Create partition
    parted /dev/$DATA_DISK --script mklabel gpt
    parted /dev/$DATA_DISK --script mkpart primary ext4 0% 100%
    sleep 2
    
    # Format partition
    echo "Formatting partition..."
    mkfs.ext4 -F /dev/${DATA_DISK}1
    
    PARTITION="${DATA_DISK}1"
else
    PARTITION=$(echo "$PARTITIONS" | head -1 | awk '{print $1}')
    echo "Using existing partition: $PARTITION"
fi

echo -e "\nStep 2: Mounting data disk"

# Create mount point
mkdir -p /var/lib/strfry

# Check if already mounted
if mount | grep -q "/dev/$PARTITION"; then
    CURRENT_MOUNT=$(mount | grep "/dev/$PARTITION" | awk '{print $3}')
    echo "Partition is already mounted at: $CURRENT_MOUNT"
    
    if [ "$CURRENT_MOUNT" != "/var/lib/strfry" ]; then
        echo "WARNING: Mounted at wrong location!"
        echo "You may need to unmount and remount:"
        echo "  sudo umount /dev/$PARTITION"
        echo "  sudo mount /dev/$PARTITION /var/lib/strfry"
        exit 1
    else
        echo "Already correctly mounted!"
    fi
else
    echo "Mounting /dev/$PARTITION to /var/lib/strfry..."
    
    # Backup existing data if any
    if [ -d "/var/lib/strfry" ] && [ "$(ls -A /var/lib/strfry 2>/dev/null)" ]; then
        echo "Backing up existing data..."
        cp -r /var/lib/strfry /tmp/strfry-backup-$(date +%Y%m%d-%H%M%S)
    fi
    
    # Mount the disk
    mount /dev/$PARTITION /var/lib/strfry
    
    if [ $? -eq 0 ]; then
        echo "Successfully mounted!"
    else
        echo "Mount failed! You may need to format the partition:"
        echo "  sudo mkfs.ext4 -F /dev/$PARTITION"
        echo "  sudo mount /dev/$PARTITION /var/lib/strfry"
        exit 1
    fi
    
    # Restore backup if it exists
    BACKUP_DIR=$(ls -d /tmp/strfry-backup-* 2>/dev/null | tail -1)
    if [ -n "$BACKUP_DIR" ]; then
        echo "Restoring backup from $BACKUP_DIR..."
        cp -r "$BACKUP_DIR"/* /var/lib/strfry/ 2>/dev/null || true
    fi
fi

echo -e "\nStep 3: Making mount permanent"

# Get UUID
DATA_UUID=$(blkid -s UUID -o value /dev/$PARTITION)
echo "Partition UUID: $DATA_UUID"

# Add to fstab
if ! grep -q "$DATA_UUID" /etc/fstab; then
    echo "Adding to /etc/fstab for permanent mounting..."
    echo "UUID=$DATA_UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab
else
    echo "Already in /etc/fstab"
fi

echo -e "\nStep 4: Setting up permissions"

# Create strfry user if doesn't exist
if ! id strfry &>/dev/null; then
    echo "Creating strfry user..."
    useradd -r -s /bin/false -d /var/lib/strfry strfry
fi

# Create directories
mkdir -p /var/lib/strfry/db
mkdir -p /var/log/strfry

# Set ownership
chown -R strfry:strfry /var/lib/strfry
chown -R strfry:strfry /var/log/strfry

# Set permissions
chmod -R 755 /var/lib/strfry
chmod -R 755 /var/log/strfry

echo -e "\nStep 5: Verification"
echo "Mount status:"
df -h /var/lib/strfry

echo -e "\nDirectory permissions:"
ls -la /var/lib/strfry/

echo -e "\nDatabase directory:"
ls -la /var/lib/strfry/db/ 2>/dev/null || echo "Database directory is empty (normal)"

# Test write access
echo -e "\nTesting write access..."
if sudo -u strfry touch /var/lib/strfry/db/test.tmp 2>/dev/null; then
    sudo -u strfry rm /var/lib/strfry/db/test.tmp
    echo "SUCCESS: strfry user can write to database directory"
else
    echo "FAILED: strfry user cannot write to database directory"
fi

echo -e "\nStep 6: Starting services"
systemctl start strfry 2>/dev/null || echo "Note: strfry service may not be configured yet"

echo -e "\n=== Data Disk Mount Complete ==="
echo "Data disk is now mounted at /var/lib/strfry"
echo "To verify everything is working:"
echo "  sudo systemctl status strfry"
echo "  sudo journalctl -u strfry -f"
