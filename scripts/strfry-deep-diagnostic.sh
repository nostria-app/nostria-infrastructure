#!/bin/bash
# Deep diagnostic script for strfry database access issues

echo "=== Strfry Deep Diagnostic ==="
echo "Timestamp: $(date)"
echo "Running as: $(whoami)"

# System information
echo -e "\n=== System Information ==="
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"

# Check if strfry binary exists and permissions
echo -e "\n=== Strfry Binary Analysis ==="
if [ -f /usr/local/bin/strfry ]; then
    echo "Strfry binary found: /usr/local/bin/strfry"
    ls -la /usr/local/bin/strfry
    echo "Binary type: $(file /usr/local/bin/strfry)"
    
    # Test execution as root
    echo "Testing execution as root..."
    if /usr/local/bin/strfry --help >/dev/null 2>&1; then
        echo "SUCCESS: Binary executes as root"
    else
        echo "FAILED: Binary does not execute as root"
    fi
    
    # Test execution as strfry user
    echo "Testing execution as strfry user..."
    if sudo -u strfry /usr/local/bin/strfry --help >/dev/null 2>&1; then
        echo "SUCCESS: Binary executes as strfry user"
    else
        echo "FAILED: Binary does not execute as strfry user"
        echo "Error output:"
        sudo -u strfry /usr/local/bin/strfry --help 2>&1 | head -3
    fi
else
    echo "ERROR: Strfry binary not found at /usr/local/bin/strfry"
fi

# Check strfry user details
echo -e "\n=== Strfry User Analysis ==="
if id strfry >/dev/null 2>&1; then
    echo "Strfry user info:"
    id strfry
    echo "Home directory: $(getent passwd strfry | cut -d: -f6)"
    echo "Shell: $(getent passwd strfry | cut -d: -f7)"
    echo "Groups: $(groups strfry)"
else
    echo "ERROR: strfry user does not exist"
fi

# Check directory structure and permissions
echo -e "\n=== Directory Structure Analysis ==="
echo "Directory tree:"
find /var/lib/strfry -type d -exec ls -ld {} \; 2>/dev/null || echo "No strfry directories found"

echo -e "\nFile ownership in /var/lib/strfry:"
find /var/lib/strfry -exec ls -la {} \; 2>/dev/null || echo "No files found"

# Check mount points and file systems
echo -e "\n=== Mount Point Analysis ==="
echo "All mounts:"
mount | grep -E "(strfry|/var)"

echo -e "\nMount options for /var/lib/strfry:"
STRFRY_MOUNT_POINT=$(df /var/lib/strfry 2>/dev/null | tail -1 | awk '{print $6}')
echo "Mount point: $STRFRY_MOUNT_POINT"
mount | grep " $STRFRY_MOUNT_POINT " || echo "Mount info not found"

# Check for SELinux
echo -e "\n=== Security Context Analysis ==="
if command -v getenforce >/dev/null 2>&1; then
    echo "SELinux status: $(getenforce)"
    if [ "$(getenforce)" != "Disabled" ]; then
        echo "SELinux contexts for strfry directories:"
        ls -Z /var/lib/strfry/ 2>/dev/null || echo "Cannot read SELinux contexts"
    fi
else
    echo "SELinux not available"
fi

# Check for AppArmor
if command -v aa-status >/dev/null 2>&1; then
    echo "AppArmor status:"
    aa-status 2>/dev/null || echo "AppArmor not active"
else
    echo "AppArmor not available"
fi

# Check disk space and inodes
echo -e "\n=== Disk Space Analysis ==="
echo "Disk space for /var/lib/strfry:"
df -h /var/lib/strfry

echo "Inode usage for /var/lib/strfry:"
df -i /var/lib/strfry

# Test file operations step by step
echo -e "\n=== File Operation Testing ==="
echo "Testing as root user:"

# Test directory creation
echo "1. Testing directory creation..."
if mkdir -p /var/lib/strfry/test 2>/dev/null; then
    echo "SUCCESS: Can create directories"
    rmdir /var/lib/strfry/test 2>/dev/null
else
    echo "FAILED: Cannot create directories"
fi

# Test file creation
echo "2. Testing file creation..."
if touch /var/lib/strfry/test.root 2>/dev/null; then
    echo "SUCCESS: Can create files as root"
    rm /var/lib/strfry/test.root 2>/dev/null
else
    echo "FAILED: Cannot create files as root"
fi

echo -e "\nTesting as strfry user:"

# Test directory creation as strfry
echo "3. Testing directory creation as strfry..."
if sudo -u strfry mkdir -p /var/lib/strfry/test 2>/dev/null; then
    echo "SUCCESS: Can create directories as strfry"
    sudo -u strfry rmdir /var/lib/strfry/test 2>/dev/null
else
    echo "FAILED: Cannot create directories as strfry"
    echo "Error: $(sudo -u strfry mkdir -p /var/lib/strfry/test 2>&1)"
fi

# Test file creation as strfry
echo "4. Testing file creation as strfry..."
if sudo -u strfry touch /var/lib/strfry/test.strfry 2>/dev/null; then
    echo "SUCCESS: Can create files as strfry"
    sudo -u strfry rm /var/lib/strfry/test.strfry 2>/dev/null
else
    echo "FAILED: Cannot create files as strfry"
    echo "Error: $(sudo -u strfry touch /var/lib/strfry/test.strfry 2>&1)"
fi

# Test database directory specifically
echo "5. Testing database directory access..."
if sudo -u strfry touch /var/lib/strfry/db/test.db 2>/dev/null; then
    echo "SUCCESS: Can create files in database directory"
    sudo -u strfry rm /var/lib/strfry/db/test.db 2>/dev/null
else
    echo "FAILED: Cannot create files in database directory"
    echo "Error: $(sudo -u strfry touch /var/lib/strfry/db/test.db 2>&1)"
    
    # Check parent directory permissions
    echo "Database directory parent permissions:"
    ls -ld /var/lib/strfry/
    ls -ld /var/lib/strfry/db/
fi

# Configuration file analysis
echo -e "\n=== Configuration Analysis ==="
if [ -f /etc/strfry/strfry.conf ]; then
    echo "Configuration file exists: /etc/strfry/strfry.conf"
    ls -la /etc/strfry/strfry.conf
    echo "Configuration content (first 20 lines):"
    head -20 /etc/strfry/strfry.conf
else
    echo "Configuration file missing: /etc/strfry/strfry.conf"
fi

# Service analysis
echo -e "\n=== Service Analysis ==="
if systemctl list-unit-files | grep -q strfry; then
    echo "Strfry service unit file:"
    systemctl cat strfry 2>/dev/null || echo "Cannot read service file"
    
    echo -e "\nService status:"
    systemctl status strfry --no-pager -l
    
    echo -e "\nRecent service logs:"
    journalctl -u strfry --no-pager -n 10
else
    echo "No strfry service found"
fi

# Process analysis
echo -e "\n=== Process Analysis ==="
echo "Running strfry processes:"
ps aux | grep strfry | grep -v grep || echo "No strfry processes running"

echo -e "\n=== Environment Analysis ==="
echo "Relevant environment variables:"
env | grep -E "(PATH|HOME|USER|SHELL)" | sort

echo -e "\n=== Diagnostic Complete ==="
echo "Save this output and check for:"
echo "1. File permission errors"
echo "2. SELinux/AppArmor denials"
echo "3. Disk space issues"
echo "4. Mount point problems"
echo "5. Binary execution issues"
