#!/bin/bash
# Enhanced remote execution script with diagnostic capabilities
# Usage: curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/run-strfry-diagnostics.sh | sudo bash

set -e

GITHUB_RAW_URL="https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts"
TEMP_DIR="/tmp/nostria-scripts"
LOG_FILE="/tmp/nostria-diagnostics.log"

# Script options
PERMISSION_SCRIPT="fix-vm-relay-permissions.sh"
DIAGNOSTIC_SCRIPT="strfry-deep-diagnostic.sh"

# Parse command line arguments
OPERATION="both"
if [ $# -gt 0 ]; then
    case "$1" in
        "fix"|"permission"|"permissions")
            OPERATION="fix"
            ;;
        "diagnostic"|"diag"|"debug")
            OPERATION="diagnostic"
            ;;
        "both"|"all")
            OPERATION="both"
            ;;
        *)
            echo "Usage: $0 [fix|diagnostic|both]"
            echo "  fix        - Run only permission fix"
            echo "  diagnostic - Run only diagnostic"
            echo "  both       - Run both (default)"
            exit 1
            ;;
    esac
fi

echo "=== Nostria Strfry Diagnostic and Fix Tool ==="
echo "Timestamp: $(date)"
echo "Running as: $(whoami)"
echo "Operation: $OPERATION"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    echo "Usage: curl -s $GITHUB_RAW_URL/run-strfry-diagnostics.sh | sudo bash"
    exit 1
fi

# Create temp directory
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Function to download script
download_script() {
    local script_name="$1"
    echo "Downloading $script_name..."
    
    if command -v curl >/dev/null 2>&1; then
        curl -s -L -o "$script_name" "$GITHUB_RAW_URL/$script_name"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$script_name" "$GITHUB_RAW_URL/$script_name"
    else
        echo "ERROR: Neither curl nor wget is available"
        exit 1
    fi
    
    # Verify download
    if [ ! -f "$script_name" ]; then
        echo "ERROR: Failed to download $script_name"
        exit 1
    fi
    
    # Check if the downloaded file looks like a script
    if ! head -1 "$script_name" | grep -q "#!/bin/bash"; then
        echo "ERROR: Downloaded file doesn't appear to be a bash script"
        echo "First line: $(head -1 "$script_name")"
        exit 1
    fi
    
    echo "Successfully downloaded $script_name ($(wc -l < "$script_name") lines)"
    chmod +x "$script_name"
}

# Function to run script with logging
run_script() {
    local script_name="$1"
    local description="$2"
    
    echo ""
    echo "=== Running $description ==="
    echo "----------------------------------------"
    
    if ./"$script_name" 2>&1 | tee -a "$LOG_FILE"; then
        echo "----------------------------------------"
        echo "SUCCESS: $description completed"
        return 0
    else
        echo "----------------------------------------"
        echo "ERROR: $description failed"
        return 1
    fi
}

# Main execution logic
case "$OPERATION" in
    "diagnostic")
        download_script "$DIAGNOSTIC_SCRIPT"
        run_script "$DIAGNOSTIC_SCRIPT" "Deep Diagnostic"
        ;;
    "fix")
        download_script "$PERMISSION_SCRIPT"
        run_script "$PERMISSION_SCRIPT" "Permission Fix"
        ;;
    "both")
        # Download both scripts
        download_script "$DIAGNOSTIC_SCRIPT"
        download_script "$PERMISSION_SCRIPT"
        
        # Run diagnostic first
        echo ""
        echo "Step 1: Running diagnostic to identify issues..."
        run_script "$DIAGNOSTIC_SCRIPT" "Deep Diagnostic"
        
        # Run permission fix
        echo ""
        echo "Step 2: Running permission fix..."
        run_script "$PERMISSION_SCRIPT" "Permission Fix"
        
        # Run diagnostic again to verify fix
        echo ""
        echo "Step 3: Running diagnostic again to verify fix..."
        run_script "$DIAGNOSTIC_SCRIPT" "Post-Fix Diagnostic"
        ;;
esac

# Show summary
echo ""
echo "=== Summary ==="
echo "- Operation: $OPERATION"
echo "- Log file: $LOG_FILE"
echo "- Temp directory: $TEMP_DIR"

# Quick status check
if systemctl is-active --quiet strfry; then
    echo "- Strfry service: RUNNING ✓"
else
    echo "- Strfry service: NOT RUNNING ✗"
fi

# Test database access
if [ -f /usr/local/bin/strfry ] && [ -f /etc/strfry/strfry.conf ]; then
    if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=1 >/dev/null 2>&1; then
        echo "- Database access: OK ✓"
    else
        echo "- Database access: FAILED ✗"
    fi
else
    echo "- Database access: CANNOT TEST (missing binary or config) ⚠️"
fi

echo ""
echo "Full diagnostic log: cat $LOG_FILE"

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
echo "=== Diagnostic and Fix Complete ==="
echo ""
echo "Usage examples:"
echo "  # Run both diagnostic and fix:"
echo "  curl -s $GITHUB_RAW_URL/run-strfry-diagnostics.sh | sudo bash"
echo ""
echo "  # Run only diagnostic:"
echo "  curl -s $GITHUB_RAW_URL/run-strfry-diagnostics.sh | sudo bash -s diagnostic"
echo ""
echo "  # Run only permission fix:"
echo "  curl -s $GITHUB_RAW_URL/run-strfry-diagnostics.sh | sudo bash -s fix"
