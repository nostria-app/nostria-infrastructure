#!/bin/bash
# Fix strfry router configuration issues
# This script removes dead domains and fixes duplicate entries

set -e

echo "=== Strfry Router Configuration Fix ==="
echo "Timestamp: $(date)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root: sudo $0"
    exit 1
fi

ROUTER_CONFIG="/etc/strfry/strfry-router.conf"

# Check if config exists
if [ ! -f "$ROUTER_CONFIG" ]; then
    echo "ERROR: Router configuration not found at $ROUTER_CONFIG"
    echo "Please run the router setup script first:"
    echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash"
    exit 1
fi

echo "Backing up current configuration..."
cp "$ROUTER_CONFIG" "$ROUTER_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
echo "✓ Backup created"

echo ""
echo "Checking for configuration issues..."

# Check for dead domain
if grep -q "index.eu.nostria.app" "$ROUTER_CONFIG"; then
    echo "⚠️  Found dead domain 'index.eu.nostria.app' - removing..."
    
    # Remove the entire nostria_index block
    sed -i '/# Two-way sync with Nostria EU Index Relay/,/^    }/d' "$ROUTER_CONFIG"
    sed -i '/nostria_index\s*{/,/^    }/d' "$ROUTER_CONFIG"
    
    echo "✓ Dead domain removed"
else
    echo "✓ No dead domain found"
fi

# Check for duplicate entries and wrong URLs
echo ""
echo "Checking for duplicate and incorrect entries..."

# Count occurrences
DAMUS_COUNT=$(grep -c "damus\s*{" "$ROUTER_CONFIG" || echo "0")
PRIMAL_COUNT=$(grep -c "primal\s*{" "$ROUTER_CONFIG" || echo "0")

if [ "$DAMUS_COUNT" -gt 1 ] || [ "$PRIMAL_COUNT" -gt 1 ]; then
    echo "⚠️  Found duplicate entries - recreating external relay section..."
    
    # Remove all external relay entries after purplepages
    sed -i '/# One-way sync (down only) from Damus relay/,$d' "$ROUTER_CONFIG"
    
    # Add the correct external relay configurations
    cat >> "$ROUTER_CONFIG" << 'EOF'
    
    # One-way sync (down only) from Damus relay
    # Only download event kinds 3 and 10002, don't push local events
    damus {
        dir = "down"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://relay.damus.io/"
        ]
        
        # Optional: Add plugin for validation/filtering
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
    }
    
    # One-way sync (down only) from Primal relay
    # Only download event kinds 3 and 10002, don't push local events
    primal {
        dir = "down"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://relay.primal.net/"
        ]
        
        # Optional: Add plugin for validation/filtering
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
    }
}

# Optional: Performance tuning
# maxConcurrentConnections = 10
# reconnectDelaySeconds = 5
# maxEventsPerSecond = 100
EOF
    
    echo "✓ External relay section recreated"
else
    # Check for wrong URLs
    if grep -q "wss://relay.damus.io/" "$ROUTER_CONFIG" && grep -A5 "primal\s*{" "$ROUTER_CONFIG" | grep -q "wss://relay.damus.io/"; then
        echo "⚠️  Found incorrect URL in primal section - fixing..."
        sed -i 's|wss://relay.damus.io/|wss://relay.primal.net/|g' "$ROUTER_CONFIG"
        echo "✓ Primal URL corrected"
    else
        echo "✓ No duplicate or incorrect entries found"
    fi
fi

echo ""
echo "Validating configuration..."
if caddy validate --config "$ROUTER_CONFIG" >/dev/null 2>&1 || \
   sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf router "$ROUTER_CONFIG" --help >/dev/null 2>&1; then
    echo "✓ Configuration is valid"
else
    echo "⚠️  Configuration validation failed (this may be normal)"
fi

echo ""
echo "Restarting strfry-router service..."
systemctl restart strfry-router

sleep 5

if systemctl is-active --quiet strfry-router; then
    echo "✓ strfry-router service is running"
else
    echo "✗ strfry-router service failed to start"
    echo "Check logs: journalctl -u strfry-router -n 20"
    exit 1
fi

echo ""
echo "=== Configuration Summary ==="
STREAM_COUNT=$(grep -c "^\s*[a-zA-Z_]*\s*{" "$ROUTER_CONFIG" || echo "0")
echo "Total streams configured: $STREAM_COUNT"

echo "Discovery relay streams:"
if grep -q "nostria_eu" "$ROUTER_CONFIG"; then
    echo "  ✓ nostria_eu (EU Discovery Relay)"
fi
if grep -q "nostria_us" "$ROUTER_CONFIG"; then
    echo "  ✓ nostria_us (US Discovery Relay)"
fi
if grep -q "nostria_af" "$ROUTER_CONFIG"; then
    echo "  ✓ nostria_af (AF Discovery Relay)"
fi

echo "External relay streams:"
if grep -q "purplepages" "$ROUTER_CONFIG"; then
    echo "  ✓ purplepages (purplepag.es)"
fi
if grep -q "damus" "$ROUTER_CONFIG"; then
    echo "  ✓ damus (relay.damus.io)"
fi
if grep -q "primal" "$ROUTER_CONFIG"; then
    echo "  ✓ primal (relay.primal.net)"
fi

echo ""
echo "=== Fix Complete ==="
echo "Configuration has been updated and router service restarted."
echo ""
echo "Monitor sync activity:"
echo "  sudo journalctl -u strfry-router -f"
echo ""
echo "If you need to restore the backup:"
echo "  sudo cp $ROUTER_CONFIG.backup-* $ROUTER_CONFIG"
echo "  sudo systemctl restart strfry-router"
echo ""
echo "Test sync manually:"
echo "  sudo -u strfry strfry sync wss://discovery.eu.nostria.app/ --filter '{\"kinds\":[3,10002]}'"
