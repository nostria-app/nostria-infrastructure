#!/bin/bash
# Fix Discovery Relay Endpoints
# This script fixes issues with HTTPS (port 443) and strfry monitoring (port 7778)

set -e

echo "=== Discovery Relay Endpoint Fix Script ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Function to restart service safely
restart_service() {
    local service=$1
    echo "Restarting $service service..."
    
    if systemctl is-active --quiet $service; then
        systemctl stop $service
        sleep 3
    fi
    
    systemctl start $service
    sleep 5
    
    if systemctl is-active --quiet $service; then
        echo "✓ $service restarted successfully"
    else
        echo "✗ Failed to restart $service"
        systemctl status $service --no-pager -l
        return 1
    fi
}

# Check if we need to fix strfry monitoring
echo "=== Checking strfry monitoring configuration ==="

if ! ss -tlnp | grep -q ':7778.*LISTEN'; then
    echo "strfry monitoring port 7778 is not listening. Checking configuration..."
    
    # Check if monitoring section exists in strfry.conf
    if ! grep -q "monitoring" /etc/strfry/strfry.conf; then
        echo "Adding monitoring configuration to strfry.conf..."
        
        # Backup original config
        cp /etc/strfry/strfry.conf /etc/strfry/strfry.conf.backup.$(date +%Y%m%d_%H%M%S)
        
        # Add monitoring section before the last closing brace or at the end
        cat >> /etc/strfry/strfry.conf << 'EOF'

# Monitoring endpoint (added by fix script)
monitoring {
    bind = "127.0.0.1"
    port = 7778
}
EOF
        echo "✓ Added monitoring configuration to strfry.conf"
    else
        echo "Monitoring configuration already exists in strfry.conf"
        echo "Current monitoring config:"
        grep -A 5 -B 2 "monitoring" /etc/strfry/strfry.conf
    fi
    
    # Restart strfry to apply monitoring configuration
    echo "Restarting strfry to enable monitoring..."
    restart_service strfry
    
    # Wait a bit for the service to fully start
    sleep 10
    
    # Test monitoring endpoint
    echo "Testing strfry monitoring endpoint..."
    if curl -s --connect-timeout 10 http://localhost:7778 > /dev/null; then
        echo "✓ strfry monitoring is now responding on port 7778"
    else
        echo "✗ strfry monitoring still not responding"
        echo "Checking if port is bound:"
        ss -tlnp | grep 7778 || echo "Port 7778 not bound"
        echo "Checking strfry logs:"
        journalctl -u strfry --no-pager -n 20
    fi
else
    echo "✓ strfry monitoring port 7778 is already listening"
fi

echo ""
echo "=== Checking HTTPS configuration ==="

if ! ss -tlnp | grep -q ':443.*LISTEN'; then
    echo "HTTPS port 443 is not listening. This is expected for initial deployment."
    echo ""
    echo "The Caddyfile is configured with 'auto_https off' to prevent certificate"
    echo "acquisition timeouts during deployment."
    echo ""
    echo "To enable HTTPS:"
    echo "1. Ensure DNS is configured: discovery.af.nostria.app points to this VM's IP"
    echo "2. Run the enable-https.sh script to transition from HTTP to HTTPS"
    echo ""
    
    # Get the discovery domain from Caddyfile
    DISCOVERY_DOMAIN=$(grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" /etc/caddy/Caddyfile | head -1 | cut -d':' -f1 | tr -d ' ')
    EXTERNAL_IP=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null || echo "UNKNOWN")
    
    echo "Current configuration:"
    echo "  Domain: $DISCOVERY_DOMAIN"
    echo "  VM External IP: $EXTERNAL_IP"
    echo ""
    echo "To check DNS configuration:"
    echo "  nslookup $DISCOVERY_DOMAIN"
    echo ""
    echo "To enable HTTPS (run after DNS is configured):"
    echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/enable-https.sh | sudo bash"
else
    echo "✓ HTTPS port 443 is already listening"
fi

echo ""
echo "=== Current Status Summary ==="
echo "Services:"
echo "  Caddy: $(systemctl is-active caddy 2>/dev/null || echo 'INACTIVE')"
echo "  strfry: $(systemctl is-active strfry 2>/dev/null || echo 'INACTIVE')"
echo ""
echo "Listening Ports:"
echo "  HTTP (80): $(ss -tlnp | grep -q ':80.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "  HTTPS (443): $(ss -tlnp | grep -q ':443.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "  strfry relay (7777): $(ss -tlnp | grep -q ':7777.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "  strfry monitoring (7778): $(ss -tlnp | grep -q ':7778.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"

echo ""
echo "=== Testing Endpoints ==="

# Test HTTP health endpoint
echo "Testing HTTP health endpoint..."
if curl -s --connect-timeout 10 http://localhost/health > /dev/null; then
    echo "✓ HTTP health endpoint responds"
else
    echo "✗ HTTP health endpoint does not respond"
fi

# Test strfry monitoring
echo "Testing strfry monitoring endpoint..."
if curl -s --connect-timeout 10 http://localhost:7778 > /dev/null; then
    echo "✓ strfry monitoring endpoint responds"
    echo "Sample response:"
    curl -s --connect-timeout 10 http://localhost:7778 | head -3
else
    echo "✗ strfry monitoring endpoint does not respond"
fi

# Test strfry relay
echo "Testing strfry relay endpoint..."
if curl -s --connect-timeout 10 http://localhost:7777 > /dev/null; then
    echo "✓ strfry relay endpoint responds"
else
    echo "✗ strfry relay endpoint does not respond"
fi

echo ""
echo "=== Fix Complete ==="
echo "Date: $(date)"

# Final recommendations
echo ""
echo "=== Next Steps ==="
if ! ss -tlnp | grep -q ':7778.*LISTEN'; then
    echo "⚠ strfry monitoring still not working. Manual intervention may be required."
    echo "  Check: journalctl -u strfry -f"
fi

if ! ss -tlnp | grep -q ':443.*LISTEN'; then
    echo "ℹ HTTPS not enabled (this is normal for initial deployment)"
    echo "  Enable after DNS configuration with enable-https.sh"
fi

echo "✓ Run 'sudo ./debug-discovery-endpoints.sh' to verify the fixes"
