#!/bin/bash
# Diagnostic script for strfry router sync issues
# This script helps troubleshoot why events aren't syncing between discovery relays

set -e

echo "=== Strfry Router Sync Diagnostics ==="
echo "Timestamp: $(date)"

# Detect current region
HOSTNAME=$(hostname)
CURRENT_REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -n "$CURRENT_REGION" ]; then
    echo "Current region: $CURRENT_REGION"
else
    echo "Region: Unknown (hostname: $HOSTNAME)"
    echo "Please enter the current region (eu, us, af):"
    read -r CURRENT_REGION
fi

echo ""
echo "=== Service Status Check ==="

# Check main strfry service
echo "Main strfry service:"
if systemctl is-active --quiet strfry; then
    echo "✓ strfry service is running"
    echo "  Status: $(systemctl is-active strfry)"
    echo "  PID: $(systemctl show --property MainPID --value strfry)"
else
    echo "✗ strfry service is not running"
    systemctl status strfry --no-pager -l || true
fi

# Check router service
echo ""
echo "Strfry router service:"
if systemctl is-active --quiet strfry-router; then
    echo "✓ strfry-router service is running"
    echo "  Status: $(systemctl is-active strfry-router)"
    echo "  PID: $(systemctl show --property MainPID --value strfry-router)"
else
    echo "✗ strfry-router service is not running"
    systemctl status strfry-router --no-pager -l || true
fi

echo ""
echo "=== Configuration Files Check ==="

# Check if router config exists
if [ -f "/etc/strfry/strfry-router.conf" ]; then
    echo "✓ Router configuration file exists"
    echo "Configuration file size: $(stat -c%s /etc/strfry/strfry-router.conf) bytes"
    
    echo ""
    echo "Router configuration content:"
    echo "----------------------------------------"
    cat /etc/strfry/strfry-router.conf
    echo "----------------------------------------"
    
    # Count stream entries
    STREAM_COUNT=$(grep -c "^\s*[a-zA-Z_]*\s*{" /etc/strfry/strfry-router.conf || echo "0")
    echo "Number of sync streams configured: $STREAM_COUNT"
    
    # Check for discovery relay entries
    echo ""
    echo "Discovery relay sync entries:"
    if grep -q "nostria_eu" /etc/strfry/strfry-router.conf; then
        echo "  ✓ nostria_eu found"
    else
        echo "  ✗ nostria_eu not found"
    fi
    
    if grep -q "nostria_us" /etc/strfry/strfry-router.conf; then
        echo "  ✓ nostria_us found"
    else
        echo "  ✗ nostria_us not found"
    fi
    
    if grep -q "nostria_af" /etc/strfry/strfry-router.conf; then
        echo "  ✓ nostria_af found"
    else
        echo "  ✗ nostria_af not found"
    fi
    
else
    echo "✗ Router configuration file not found at /etc/strfry/strfry-router.conf"
fi

# Check main strfry config
echo ""
if [ -f "/etc/strfry/strfry.conf" ]; then
    echo "✓ Main strfry configuration file exists"
else
    echo "✗ Main strfry configuration file not found at /etc/strfry/strfry.conf"
fi

echo ""
echo "=== Network Connectivity Check ==="

# Test connectivity to other discovery relays
DISCOVERY_RELAYS=("discovery.eu.nostria.app" "discovery.us.nostria.app" "discovery.af.nostria.app")

for relay in "${DISCOVERY_RELAYS[@]}"; do
    if [ "$relay" != "discovery.$CURRENT_REGION.nostria.app" ]; then
        echo "Testing connectivity to $relay..."
        
        # Test HTTP/HTTPS
        if curl -s --connect-timeout 10 "https://$relay/health" >/dev/null 2>&1; then
            echo "  ✓ HTTPS connectivity successful"
        elif curl -s --connect-timeout 10 "http://$relay/health" >/dev/null 2>&1; then
            echo "  ⚠️  HTTP works but HTTPS failed"
        else
            echo "  ✗ No HTTP/HTTPS connectivity"
        fi
        
        # Test WebSocket (quick check)
        if timeout 5 bash -c "exec 3<>/dev/tcp/$relay/443" 2>/dev/null; then
            echo "  ✓ TCP port 443 is open"
            exec 3<&-
            exec 3>&-
        else
            echo "  ✗ TCP port 443 is not accessible"
        fi
    fi
done

echo ""
echo "=== Event Database Check ==="

# Check event counts
echo "Current event counts in database:"
echo "Contact lists (kind 3):"
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan '{"kinds":[3]}' 2>/dev/null | wc -l || echo "Error scanning kind 3 events"

echo "Relay lists (kind 10002):"
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan '{"kinds":[10002]}' 2>/dev/null | wc -l || echo "Error scanning kind 10002 events"

# Show recent events
echo ""
echo "Recent kind 10002 events (last 5):"
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan '{"kinds":[10002],"limit":5}' 2>/dev/null | \
    jq -r '.created_at as $timestamp | .pubkey[0:8] + " " + ($timestamp | todate) + " " + (.content | length | tostring) + " chars"' 2>/dev/null || \
    echo "No recent kind 10002 events found or jq not available"

echo ""
echo "=== Router Service Logs ==="

# Show recent router logs
echo "Recent strfry-router logs (last 20 lines):"
journalctl -u strfry-router --no-pager -n 20 --since "1 hour ago" || echo "No recent router logs found"

echo ""
echo "=== Main Relay Logs ==="

# Show recent main relay logs
echo "Recent strfry logs (last 10 lines):"
journalctl -u strfry --no-pager -n 10 --since "1 hour ago" || echo "No recent strfry logs found"

echo ""
echo "=== Process Information ==="

# Check running processes
echo "Strfry processes:"
ps aux | grep -E "(strfry|router)" | grep -v grep || echo "No strfry processes found"

echo ""
echo "Network connections on relay ports:"
ss -tuln | grep -E "(7777|443|80)" || echo "No relay port connections found"

echo ""
echo "=== Configuration Validation ==="

# Test router configuration
echo "Testing router configuration syntax..."
if command -v strfry &> /dev/null; then
    if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf router /etc/strfry/strfry-router.conf --help >/dev/null 2>&1; then
        echo "✓ Router configuration syntax appears valid"
    else
        echo "⚠️  Cannot validate router configuration (may be normal)"
    fi
else
    echo "✗ strfry binary not found"
fi

echo ""
echo "=== Manual Sync Test ==="

# Test manual sync with one relay
echo "Testing manual sync with discovery relay (if not current region)..."

if [ "$CURRENT_REGION" != "eu" ]; then
    TEST_RELAY="wss://discovery.eu.nostria.app/"
    TEST_NAME="EU Discovery Relay"
elif [ "$CURRENT_REGION" != "us" ]; then
    TEST_RELAY="wss://discovery.us.nostria.app/"
    TEST_NAME="US Discovery Relay"
else
    TEST_RELAY="wss://discovery.af.nostria.app/"
    TEST_NAME="AF Discovery Relay"
fi

echo "Testing sync with $TEST_NAME..."
echo "Command: sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf sync '$TEST_RELAY' --filter '{\"kinds\":[10002]}' --limit 1"

if timeout 30 sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf sync "$TEST_RELAY" --filter '{"kinds":[10002]}' --limit 1 2>&1; then
    echo "✓ Manual sync test completed"
else
    echo "✗ Manual sync test failed or timed out"
fi

echo ""
echo "=== Recommendations ==="

# Check if router service is running
if ! systemctl is-active --quiet strfry-router; then
    echo "🔧 Router service is not running. Start it with:"
    echo "   sudo systemctl start strfry-router"
    echo "   sudo systemctl enable strfry-router"
fi

# Check if configuration is missing discovery relays
if [ -f "/etc/strfry/strfry-router.conf" ]; then
    MISSING_RELAYS=false
    
    if [ "$CURRENT_REGION" != "eu" ] && ! grep -q "nostria_eu" /etc/strfry/strfry-router.conf; then
        echo "🔧 Missing EU discovery relay configuration"
        MISSING_RELAYS=true
    fi
    
    if [ "$CURRENT_REGION" != "us" ] && ! grep -q "nostria_us" /etc/strfry/strfry-router.conf; then
        echo "🔧 Missing US discovery relay configuration"
        MISSING_RELAYS=true
    fi
    
    if [ "$CURRENT_REGION" != "af" ] && ! grep -q "nostria_af" /etc/strfry/strfry-router.conf; then
        echo "🔧 Missing AF discovery relay configuration"
        MISSING_RELAYS=true
    fi
    
    if [ "$MISSING_RELAYS" = true ]; then
        echo "   Re-run router setup: curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash"
    fi
fi

# Check connectivity issues
echo ""
echo "🔧 If connectivity issues were found:"
echo "   - Verify DNS resolution: nslookup discovery.eu.nostria.app"
echo "   - Check firewall rules: sudo ufw status"
echo "   - Test manual curl: curl -v https://discovery.eu.nostria.app/health"

echo ""
echo "🔧 To restart router service:"
echo "   sudo systemctl restart strfry-router"
echo "   sudo journalctl -u strfry-router -f"

echo ""
echo "🔧 To force a manual sync:"
echo "   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash"

echo ""
echo "=== Diagnostics Complete ==="
echo "Review the output above to identify potential issues with strfry router sync."
