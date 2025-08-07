#!/bin/bash
# Script to add and configure a data disk for existing VM relay
# This script adds a 32GB data disk and sets up proper mounting for strfry database

echo "=== VM Relay Data Disk Setup for Existing VM ==="
echo "Timestamp: $(date)"

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Check if strfry service exists
if ! systemctl list-units --full -all | grep -Fq "strfry.service"; then
    echo "ERROR: strfry service not found. Please run the main VM setup first."
    exit 1
fi

# Check if strfry user exists
if ! id strfry &>/dev/null; then
    echo "ERROR: strfry user does not exist. Please run the main VM setup first."
    exit 1
fi

echo "Step 1: Checking current disk configuration..."
echo "Current disk layout:"
lsblk -f

echo -e "\nCurrent mount points:"
df -h | grep -E "(Filesystem|/var/lib/strfry|/$)"

# Check if /var/lib/strfry is already on a separate disk
STRFRY_MOUNT=$(df /var/lib/strfry 2>/dev/null | tail -1 | awk '{print $1}')
ROOT_MOUNT=$(df / 2>/dev/null | tail -1 | awk '{print $1}')

if [ "$STRFRY_MOUNT" != "$ROOT_MOUNT" ] && [[ "$STRFRY_MOUNT" =~ ^/dev/ ]]; then
    echo "INFO: /var/lib/strfry is already on separate disk: $STRFRY_MOUNT"
    echo "No additional disk setup needed. Checking permissions..."
    
    # Just fix permissions and exit
    echo "Ensuring proper ownership..."
    chown -R strfry:strfry /var/lib/strfry
    chmod -R 755 /var/lib/strfry
    
    echo "Data disk is already configured. Setup complete!"
    exit 0
fi

echo -e "\nStep 2: Looking for unpartitioned data disks..."

# Find the data disk (should be the first unpartitioned disk that's not the OS disk)
ROOT_DISK=$(df / | tail -1 | awk '{print $1}' | sed 's/[0-9]*$//' | sed 's|/dev/||')
echo "Root disk identified as: $ROOT_DISK"

# Find data disk by looking for unpartitioned disks
DATA_DISK=$(lsblk -dn -o NAME,TYPE | grep "disk" | grep -v "$ROOT_DISK" | head -n1 | awk '{print $1}')

if [ -z "$DATA_DISK" ]; then
    echo "ERROR: No additional data disk found!"
    echo "You need to attach a data disk to this VM in Azure Portal first."
    echo ""
    echo "To add a data disk in Azure Portal:"
    echo "1. Go to Azure Portal -> Virtual Machines -> [Your VM]"
    echo "2. Click 'Disks' in the left menu"
    echo "3. Click '+ Create and attach a new disk'"
    echo "4. Set size to 32 GB, type to Standard SSD"
    echo "5. Click 'Save'"
    echo "6. Wait for the disk to be attached, then run this script again"
    exit 1
fi

echo "Found data disk: /dev/$DATA_DISK"

# Check if the disk already has partitions
if [ $(lsblk -n /dev/$DATA_DISK | wc -l) -gt 1 ]; then
    echo "Data disk already has partitions. Checking existing setup..."
    PARTITION="${DATA_DISK}1"
    
    if mount | grep -q "/dev/$PARTITION"; then
        echo "Data disk partition is already mounted"
        # Check if it's mounted to the right place
        CURRENT_MOUNT=$(mount | grep "/dev/$PARTITION" | awk '{print $3}')
        if [ "$CURRENT_MOUNT" != "/var/lib/strfry" ]; then
            echo "WARNING: Data disk is mounted to $CURRENT_MOUNT instead of /var/lib/strfry"
            echo "This needs manual intervention"
            exit 1
        fi
    else
        echo "Mounting existing data disk partition..."
        mkdir -p /var/lib/strfry
        mount /dev/$PARTITION /var/lib/strfry || {
            echo "Failed to mount existing partition, will reformat..."
            umount /var/lib/strfry 2>/dev/null || true
            mkfs.ext4 -F /dev/$PARTITION
            mount /dev/$PARTITION /var/lib/strfry
        }
    fi
else
    echo "Step 3: Preparing data disk..."
    
    # Stop strfry service temporarily
    echo "Stopping strfry service..."
    systemctl stop strfry
    
    # Backup existing data if any
    if [ -d "/var/lib/strfry" ] && [ "$(ls -A /var/lib/strfry 2>/dev/null)" ]; then
        echo "Backing up existing strfry data..."
        mkdir -p /tmp/strfry-backup
        cp -r /var/lib/strfry/* /tmp/strfry-backup/ 2>/dev/null || true
        echo "Backup created in /tmp/strfry-backup/"
    fi
    
    echo "Creating partition on data disk..."
    # Create partition table and partition
    parted /dev/$DATA_DISK --script mklabel gpt
    parted /dev/$DATA_DISK --script mkpart primary ext4 0% 100%
    
    # Wait for partition to be recognized
    echo "Waiting for partition to be recognized..."
    sleep 3
    
    # Format the partition with ext4
    echo "Formatting partition..."
    mkfs.ext4 -F /dev/${DATA_DISK}1
    
    # Create mount point and mount the disk
    echo "Mounting data disk..."
    mkdir -p /var/lib/strfry
    mount /dev/${DATA_DISK}1 /var/lib/strfry
    
    # Restore backup if it exists
    if [ -d "/tmp/strfry-backup" ] && [ "$(ls -A /tmp/strfry-backup 2>/dev/null)" ]; then
        echo "Restoring strfry data from backup..."
        cp -r /tmp/strfry-backup/* /var/lib/strfry/
        rm -rf /tmp/strfry-backup
    fi
fi

echo "Step 4: Configuring permanent mounting..."

# Get UUID for permanent mounting
DATA_UUID=$(blkid -s UUID -o value /dev/${DATA_DISK}1)
echo "Data disk UUID: $DATA_UUID"

# Add to fstab for permanent mounting (remove any existing entry first)
sed -i '\|/var/lib/strfry|d' /etc/fstab
echo "UUID=$DATA_UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab

echo "Step 5: Setting proper ownership and permissions..."

# Create database directory
mkdir -p /var/lib/strfry/db
mkdir -p /var/log/strfry

# Set proper ownership and permissions
chown -R strfry:strfry /var/lib/strfry
chown -R strfry:strfry /var/log/strfry
chmod -R 755 /var/lib/strfry
chmod -R 755 /var/log/strfry

# Ensure database directory has correct permissions
chmod 755 /var/lib/strfry/db
chown strfry:strfry /var/lib/strfry/db

echo "Step 6: Verifying setup..."

# Verify mount
echo "Mount verification:"
df -h /var/lib/strfry

echo "Directory permissions:"
ls -la /var/lib/strfry/

echo "Database directory:"
ls -la /var/lib/strfry/db/ 2>/dev/null || echo "Database directory is empty (normal for new setup)"

# Test write access
echo "Testing write access..."
if sudo -u strfry touch /var/lib/strfry/test.tmp 2>/dev/null; then
    sudo -u strfry rm /var/lib/strfry/test.tmp
    echo "SUCCESS: strfry user can write to data disk"
else
    echo "ERROR: strfry user cannot write to data disk"
    exit 1
fi

echo "Step 7: Starting services..."

# Start strfry service
systemctl start strfry
sleep 5

# Check if strfry started successfully
if systemctl is-active --quiet strfry; then
    echo "SUCCESS: strfry service started successfully"
else
    echo "WARNING: strfry service may have issues. Checking logs..."
    journalctl -u strfry --no-pager -n 10
fi

echo -e "\n=== Data Disk Setup Complete ==="
echo "Data disk information:"
echo "  Device: /dev/${DATA_DISK}1"
echo "  UUID: $DATA_UUID"
echo "  Mount point: /var/lib/strfry"
echo "  Size: $(df -h /var/lib/strfry | tail -1 | awk '{print $2}')"
echo "  Usage: $(df -h /var/lib/strfry | tail -1 | awk '{print $5}')"
echo ""
echo "Next steps:"
echo "1. Verify the relay is working: sudo /usr/local/bin/strfry-health-check.sh"
echo "2. Check service status: sudo systemctl status strfry"
echo "3. Monitor logs: sudo journalctl -u strfry -f"
echo ""
echo "The data disk will automatically mount on reboot via fstab entry."
