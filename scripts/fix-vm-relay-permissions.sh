#!/bin/bash
# Fix strfry permission issues on mounted data disk for VM relays

echo "=== Strfry Permission Diagnosis and Fix for VM Relay ==="
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

# First check if strfry config exists
if [ ! -f /etc/strfry/strfry.conf ]; then
    echo "WARNING: /etc/strfry/strfry.conf does not exist"
    echo "Creating basic configuration..."
    cat > /etc/strfry/strfry.conf << 'EOF'
{
    "relay": {
        "bind": "0.0.0.0",
        "port": 7777,
        "nofiles": 1000000,
        "realIpHeader": ""
    },
    "db": {
        "dbParams": {
            "path": "/var/lib/strfry/db/"
        },
        "dblogPath": "/var/lib/strfry/db/log",
        "maxOpenFiles": 256
    },
    "events": {
        "rejectEventsNewerThanSeconds": 900,
        "rejectEventsOlderThanSeconds": 94608000,
        "rejectEphemeralEventsOlderThanSeconds": 60,
        "ephemeralEventsLifetimeSeconds": 300,
        "maxEventBytes": 16384
    },
    "relay": {
        "compression": false,
        "compressionLevel": 6
    }
}
EOF
    chown root:root /etc/strfry/strfry.conf
    chmod 644 /etc/strfry/strfry.conf
fi

# Test basic file system access
echo "Testing file system access as strfry user..."
if sudo -u strfry touch /var/lib/strfry/db/test.tmp 2>/dev/null && sudo -u strfry rm /var/lib/strfry/db/test.tmp 2>/dev/null; then
    echo "SUCCESS: strfry user can write to database directory"
else
    echo "FAILED: strfry user cannot write to database directory"
    echo "Checking detailed permissions..."
    ls -la /var/lib/strfry/
    ls -la /var/lib/strfry/db/
    
    # Try to fix again with more aggressive permissions
    echo "Applying more aggressive permission fix..."
    chown -R strfry:strfry /var/lib/strfry
    chmod -R 755 /var/lib/strfry
    
    # Test again
    if sudo -u strfry touch /var/lib/strfry/db/test2.tmp 2>/dev/null && sudo -u strfry rm /var/lib/strfry/db/test2.tmp 2>/dev/null; then
        echo "SUCCESS: strfry user can now write to database directory"
    else
        echo "FAILED: Still cannot write - possible SELinux or other security context issue"
        # Check for SELinux
        if command -v getenforce >/dev/null 2>&1; then
            echo "SELinux status: $(getenforce 2>/dev/null || echo 'Not available')"
        fi
    fi
fi

# Test strfry binary execution
echo "Testing strfry binary execution as strfry user..."
if sudo -u strfry /usr/local/bin/strfry --help >/dev/null 2>&1; then
    echo "SUCCESS: strfry binary can be executed by strfry user"
else
    echo "WARNING: strfry binary execution failed"
fi

# Test strfry database access
echo "Testing strfry database access..."
if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=1 >/dev/null 2>&1; then
    echo "SUCCESS: strfry can access database without permission errors"
else
    echo "ERROR: strfry database access failed"
    echo "Attempting to show detailed error..."
    sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=1 2>&1 | head -5
    
    # Check if database files exist and their permissions
    if [ -f /var/lib/strfry/db/data.mdb ]; then
        echo "Database file permissions:"
        ls -la /var/lib/strfry/db/data.mdb
        ls -la /var/lib/strfry/db/lock.mdb 2>/dev/null || echo "No lock file"
    else
        echo "No database files found - this might be expected for a fresh installation"
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
