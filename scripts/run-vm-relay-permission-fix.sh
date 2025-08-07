#!/bin/bash
# Remote execution script for strfry permission fixes on VM relays
# Usage: curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/run-vm-relay-permission-fix.sh | sudo bash

set -e

SCRIPT_NAME="fix-vm-relay-permissions.sh"
GITHUB_RAW_URL="https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts"
TEMP_DIR="/tmp/nostria-scripts"
LOG_FILE="/tmp/nostria-permission-fix.log"

echo "=== Nostria VM Relay Permission Fix Runner ==="
echo "Timestamp: $(date)"
echo "Running as: $(whoami)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    echo "Usage: curl -s $GITHUB_RAW_URL/run-vm-relay-permission-fix.sh | sudo bash"
    exit 1
fi

# Create temp directory
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Download the permission fix script
echo "Downloading permission fix script..."
if command -v curl >/dev/null 2>&1; then
    curl -s -L -o "$SCRIPT_NAME" "$GITHUB_RAW_URL/$SCRIPT_NAME"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$SCRIPT_NAME" "$GITHUB_RAW_URL/$SCRIPT_NAME"
else
    echo "ERROR: Neither curl nor wget is available"
    exit 1
fi

# Verify download
if [ ! -f "$SCRIPT_NAME" ]; then
    echo "ERROR: Failed to download $SCRIPT_NAME"
    exit 1
fi

# Check if the downloaded file looks like a script
if ! head -1 "$SCRIPT_NAME" | grep -q "#!/bin/bash"; then
    echo "ERROR: Downloaded file doesn't appear to be a bash script"
    echo "First line: $(head -1 "$SCRIPT_NAME")"
    exit 1
fi

echo "Successfully downloaded $SCRIPT_NAME ($(wc -l < "$SCRIPT_NAME") lines)"

# Make script executable
chmod +x "$SCRIPT_NAME"

# Run the permission fix script with logging
echo "Running permission fix script..."
echo "Output will be logged to: $LOG_FILE"
echo "----------------------------------------"

# Execute the script and capture output
if ./"$SCRIPT_NAME" 2>&1 | tee "$LOG_FILE"; then
    echo "----------------------------------------"
    echo "SUCCESS: Permission fix script completed successfully"
    
    # Show summary
    echo ""
    echo "=== Summary ==="
    echo "- Script executed: $SCRIPT_NAME"
    echo "- Log file: $LOG_FILE"
    echo "- Temp directory: $TEMP_DIR"
    
    # Check strfry service status
    if systemctl is-active --quiet strfry; then
        echo "- Strfry service: RUNNING ✓"
    else
        echo "- Strfry service: NOT RUNNING ✗"
    fi
    
    # Check if strfry can access database
    if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=1 >/dev/null 2>&1; then
        echo "- Database access: OK ✓"
    else
        echo "- Database access: FAILED ✗"
    fi
    
    echo ""
    echo "You can view the full log with: cat $LOG_FILE"
    
else
    echo "----------------------------------------"
    echo "ERROR: Permission fix script failed"
    echo "Check the log file for details: $LOG_FILE"
    exit 1
fi

# Cleanup option
echo ""
read -p "Remove temporary files? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    rm -rf "$TEMP_DIR"
    echo "Temporary files removed"
else
    echo "Temporary files kept in: $TEMP_DIR"
fi

echo ""
echo "=== Permission Fix Complete ==="
echo "If you need to run this again: curl -s $GITHUB_RAW_URL/run-vm-relay-permission-fix.sh | sudo bash"
