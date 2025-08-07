#!/bin/bash
# Fix strfry permission issues on mounted data disk

echo "=== Strfry Permission Diagnosis and Fix ==="
echo "Timestamp: $(date)"

# Check if strfry user exists
if ! id strfry &>/dev/null; then
    echo "ERROR: strfry user does not exist"
    echo "Creating strfry user..."
    useradd -r -s /bin/false -d /var/lib/strfry strfry
else
    echo "OK: strfry user exists"
fi

# Check mount points
echo -e "\n=== Mount Point Analysis ==="
echo "Current mounts:"
df -h | grep -E "(Filesystem|/var/lib/strfry|/$)"

# Check if /var/lib/strfry is on a separate mount
STRFRY_MOUNT=$(df /var/lib/strfry 2>/dev/null | tail -1 | awk '{print $1}')
ROOT_MOUNT=$(df / 2>/dev/null | tail -1 | awk '{print $1}')

if [ "$STRFRY_MOUNT" != "$ROOT_MOUNT" ]; then
    echo "INFO: /var/lib/strfry is on separate mount: $STRFRY_MOUNT"
else
    echo "WARNING: /var/lib/strfry appears to be on root filesystem: $STRFRY_MOUNT"
fi

# Check current ownership and permissions
echo -e "\n=== Current Ownership and Permissions ==="
echo "/var/lib/strfry:"
ls -la /var/lib/strfry/ 2>/dev/null || echo "Directory does not exist"

echo "/var/lib/strfry/db:"
ls -la /var/lib/strfry/db/ 2>/dev/null || echo "Database directory does not exist or is empty"

# Check strfry process and service
echo -e "\n=== Strfry Service Status ==="
systemctl status strfry --no-pager -l || echo "Service not running"

echo -e "\n=== Strfry Process Check ==="
ps aux | grep strfry | grep -v grep || echo "No strfry processes running"

# Fix permissions
echo -e "\n=== Fixing Permissions ==="

# Stop strfry service if running
if systemctl is-active --quiet strfry; then
    echo "Stopping strfry service..."
    systemctl stop strfry
fi

# Create directories if they don't exist
echo "Creating required directories..."
mkdir -p /var/lib/strfry/db
mkdir -p /var/log/strfry
mkdir -p /etc/strfry

# Set proper ownership
echo "Setting proper ownership..."
chown -R strfry:strfry /var/lib/strfry
chown -R strfry:strfry /var/log/strfry
chown root:root /etc/strfry

# Set proper permissions
echo "Setting proper permissions..."
chmod -R 755 /var/lib/strfry
chmod -R 755 /var/log/strfry
chmod 755 /etc/strfry

# Special attention to database directory
echo "Setting database directory permissions..."
chmod 755 /var/lib/strfry/db
chown strfry:strfry /var/lib/strfry/db

# If there are existing database files, fix their ownership too
if [ -f /var/lib/strfry/db/data.mdb ]; then
    echo "Fixing existing database file ownership..."
    chown strfry:strfry /var/lib/strfry/db/data.mdb
    chown strfry:strfry /var/lib/strfry/db/lock.mdb 2>/dev/null || true
    chmod 644 /var/lib/strfry/db/data.mdb
    chmod 644 /var/lib/strfry/db/lock.mdb 2>/dev/null || true
fi

# Verify the fix
echo -e "\n=== Verification After Fix ==="
echo "/var/lib/strfry:"
ls -la /var/lib/strfry/

echo "/var/lib/strfry/db:"
ls -la /var/lib/strfry/db/

# Test strfry as the strfry user
echo -e "\n=== Testing Strfry Access ==="
echo "Testing strfry export command as strfry user..."
if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=1 >/dev/null 2>&1; then
    echo "SUCCESS: strfry can access database without permission errors"
else
    echo "ERROR: strfry still has permission issues"
    echo "Attempting to initialize database..."
    sudo -u strfry touch /var/lib/strfry/db/test.tmp && sudo -u strfry rm /var/lib/strfry/db/test.tmp
    if [ $? -eq 0 ]; then
        echo "SUCCESS: strfry user can write to database directory"
    else
        echo "FAILED: strfry user cannot write to database directory"
    fi
fi

# Start strfry service
echo -e "\n=== Starting Strfry Service ==="
systemctl start strfry
sleep 5

if systemctl is-active --quiet strfry; then
    echo "SUCCESS: strfry service started successfully"
else
    echo "ERROR: strfry service failed to start"
    echo "Recent logs:"
    journalctl -u strfry --no-pager -n 10
fi

echo -e "\n=== Fix Complete ==="
echo "If you're still having issues, check the logs:"
echo "  sudo journalctl -u strfry -f"
echo "  sudo tail -f /var/log/strfry/strfry.log"
