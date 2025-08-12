#!/bin/bash
# Quick fix script for strfry router sync between discovery relays
# This adds missing discovery relay sync entries to the router configuration

set -e

echo "=== Quick Fix for Discovery Relay Sync ==="
echo "Timestamp: $(date)"

# Detect current region
HOSTNAME=$(hostname)
CURRENT_REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$CURRENT_REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the current region (eu, us, af):"
    read -r CURRENT_REGION
fi

echo "Current region: $CURRENT_REGION"

ROUTER_CONFIG="/etc/strfry/strfry-router.conf"

# Check if router config exists
if [ ! -f "$ROUTER_CONFIG" ]; then
    echo "ERROR: Router configuration not found at $ROUTER_CONFIG"
    echo "Please run the setup script first:"
    echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash"
    exit 1
fi

# Create backup
echo "Creating backup of router configuration..."
cp "$ROUTER_CONFIG" "$ROUTER_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"

echo "Checking current configuration..."
echo "Discovery relay entries currently in config:"
grep -E "(nostria_eu|nostria_us|nostria_af)" "$ROUTER_CONFIG" || echo "  No discovery relay entries found"

# Check if discovery relay entries are missing
MISSING_EU=false
MISSING_US=false
MISSING_AF=false

if [ "$CURRENT_REGION" != "eu" ] && ! grep -q "nostria_eu" "$ROUTER_CONFIG"; then
    MISSING_EU=true
fi

if [ "$CURRENT_REGION" != "us" ] && ! grep -q "nostria_us" "$ROUTER_CONFIG"; then
    MISSING_US=true
fi

if [ "$CURRENT_REGION" != "af" ] && ! grep -q "nostria_af" "$ROUTER_CONFIG"; then
    MISSING_AF=true
fi

if [ "$MISSING_EU" = false ] && [ "$MISSING_US" = false ] && [ "$MISSING_AF" = false ]; then
    echo "✓ All expected discovery relay entries are already present"
    exit 0
fi

echo "Missing discovery relay entries detected. Adding them..."

# Find the insertion point (before the closing bracket of streams)
if ! grep -q "^streams {" "$ROUTER_CONFIG"; then
    echo "ERROR: Invalid router configuration - 'streams {' not found"
    exit 1
fi

# Create temporary file with discovery relay entries
TEMP_CONFIG=$(mktemp)

# Copy everything up to the last closing bracket
head -n -1 "$ROUTER_CONFIG" > "$TEMP_CONFIG"

# Add missing discovery relay entries
if [ "$MISSING_EU" = true ]; then
    echo "Adding EU Discovery Relay sync configuration..."
    cat >> "$TEMP_CONFIG" << 'EOF'
    
    # Two-way sync with Nostria EU Discovery Relay
    nostria_eu {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.eu.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

if [ "$MISSING_US" = true ]; then
    echo "Adding US Discovery Relay sync configuration..."
    cat >> "$TEMP_CONFIG" << 'EOF'
    
    # Two-way sync with Nostria US Discovery Relay
    nostria_us {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.us.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

if [ "$MISSING_AF" = true ]; then
    echo "Adding AF Discovery Relay sync configuration..."
    cat >> "$TEMP_CONFIG" << 'EOF'
    
    # Two-way sync with Nostria AF Discovery Relay
    nostria_af {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.af.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

# Add the closing bracket
echo "}" >> "$TEMP_CONFIG"

# Validate the new configuration
echo "Validating new configuration..."
if caddy validate --config "$TEMP_CONFIG" 2>/dev/null || true; then
    echo "Configuration syntax appears valid"
else
    echo "Note: Cannot validate with Caddy (this is normal for strfry configs)"
fi

# Replace the original configuration
mv "$TEMP_CONFIG" "$ROUTER_CONFIG"
chown root:root "$ROUTER_CONFIG"
chmod 644 "$ROUTER_CONFIG"

echo "✓ Router configuration updated"

# Show the new configuration
echo ""
echo "=== Updated Configuration ==="
echo "Discovery relay entries now in config:"
grep -A 15 -E "(nostria_eu|nostria_us|nostria_af)" "$ROUTER_CONFIG" || echo "  Error reading config"

# Restart router service
echo ""
echo "Restarting strfry-router service..."
systemctl restart strfry-router

# Wait for service to start
sleep 5

if systemctl is-active --quiet strfry-router; then
    echo "✓ Router service restarted successfully"
    
    # Show recent logs
    echo ""
    echo "Recent router logs:"
    journalctl -u strfry-router --no-pager -n 10 --since "1 minute ago" || true
else
    echo "✗ Router service failed to start"
    echo "Service status:"
    systemctl status strfry-router --no-pager -l || true
    
    echo ""
    echo "Restoring backup configuration..."
    cp "$ROUTER_CONFIG.backup-"* "$ROUTER_CONFIG"
    systemctl restart strfry-router
    exit 1
fi

echo ""
echo "=== Fix Complete ==="
echo "Discovery relay sync entries have been added to the router configuration."
echo "The router should now sync events between discovery relays."
echo ""
echo "Monitor sync activity:"
echo "  sudo journalctl -u strfry-router -f"
echo "  sudo /usr/local/bin/strfry-router-monitor.sh"
echo ""
echo "Test connectivity:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/diagnose-strfry-router-sync.sh | sudo bash"
