#!/bin/bash
# Debug Discovery Relay Endpoints
# This script diagnoses issues with HTTPS (port 443) and strfry monitoring (port 7778)

echo "=== Discovery Relay Endpoint Diagnostics ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Function to check if a port is listening
check_port() {
    local port=$1
    local service=$2
    echo "Checking port $port ($service)..."
    
    if ss -tlnp | grep -q ":$port.*LISTEN"; then
        echo "✓ Port $port is listening"
        ss -tlnp | grep ":$port.*LISTEN"
    else
        echo "✗ Port $port is NOT listening"
    fi
    echo ""
}

# Function to check service status
check_service() {
    local service=$1
    echo "Checking $service service status..."
    
    if systemctl is-active --quiet $service; then
        echo "✓ $service is active"
        systemctl status $service --no-pager -l | head -10
    else
        echo "✗ $service is NOT active"
        systemctl status $service --no-pager -l | head -10
    fi
    echo ""
}

# Check basic network connectivity
echo "=== Network Interface Check ==="
ip addr show | grep -E "(inet|UP|DOWN)"
echo ""

# Check listening ports
echo "=== Port Status Check ==="
check_port "80" "Caddy HTTP"
check_port "443" "Caddy HTTPS"
check_port "7777" "strfry relay"
check_port "7778" "strfry monitoring"

# Check service statuses
echo "=== Service Status Check ==="
check_service "caddy"
check_service "strfry"

# Check Caddy configuration
echo "=== Caddy Configuration Analysis ==="
echo "Caddyfile contents:"
if [ -f "/etc/caddy/Caddyfile" ]; then
    cat /etc/caddy/Caddyfile | head -20
    echo "..."
    
    echo ""
    echo "HTTPS Status in Caddyfile:"
    if grep -q "auto_https off" /etc/caddy/Caddyfile; then
        echo "✗ HTTPS is disabled (auto_https off)"
    else
        echo "✓ HTTPS should be enabled"
    fi
    
    echo ""
    echo "Domains configured:"
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" /etc/caddy/Caddyfile || echo "No domains found"
else
    echo "✗ Caddyfile not found at /etc/caddy/Caddyfile"
fi
echo ""

# Check strfry configuration for monitoring
echo "=== Strfry Monitoring Configuration ==="
if [ -f "/etc/strfry/strfry.conf" ]; then
    echo "Monitoring section in strfry.conf:"
    grep -A 5 -B 2 "monitoring" /etc/strfry/strfry.conf || echo "No monitoring section found"
else
    echo "✗ strfry.conf not found at /etc/strfry/strfry.conf"
fi
echo ""

# Check strfry process and arguments
echo "=== Strfry Process Check ==="
if pgrep -f strfry > /dev/null; then
    echo "✓ strfry process is running"
    ps aux | grep strfry | grep -v grep
    echo ""
    echo "Process details:"
    pgrep -f strfry | xargs -I {} ps -p {} -o pid,ppid,user,cmd --no-headers
else
    echo "✗ strfry process is NOT running"
fi
echo ""

# Test local connections
echo "=== Local Connection Tests ==="
echo "Testing strfry relay (port 7777):"
if curl -s --connect-timeout 5 http://localhost:7777 > /dev/null 2>&1; then
    echo "✓ strfry relay responds on localhost:7777"
else
    echo "✗ strfry relay does not respond on localhost:7777"
fi

echo ""
echo "Testing strfry monitoring (port 7778):"
if curl -s --connect-timeout 5 http://localhost:7778 > /dev/null 2>&1; then
    echo "✓ strfry monitoring responds on localhost:7778"
    echo "Response:"
    curl -s --connect-timeout 5 http://localhost:7778 | head -10
else
    echo "✗ strfry monitoring does not respond on localhost:7778"
fi

echo ""
echo "Testing Caddy admin API (port 2019):"
if curl -s --connect-timeout 5 http://localhost:2019 > /dev/null 2>&1; then
    echo "✓ Caddy admin API responds on localhost:2019"
else
    echo "✗ Caddy admin API does not respond on localhost:2019"
fi

# Check recent logs
echo ""
echo "=== Recent Service Logs ==="
echo "Last 10 lines of Caddy logs:"
journalctl -u caddy --no-pager -n 10 2>/dev/null || echo "No Caddy logs available"

echo ""
echo "Last 10 lines of strfry logs:"
journalctl -u strfry --no-pager -n 10 2>/dev/null || echo "No strfry logs available"

# Check firewall
echo ""
echo "=== Firewall Status ==="
if command -v ufw >/dev/null 2>&1; then
    echo "UFW status:"
    ufw status
else
    echo "UFW not available"
fi

# DNS resolution check
echo ""
echo "=== DNS Resolution Check ==="
DISCOVERY_DOMAIN=$(grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" /etc/caddy/Caddyfile | head -1 | cut -d':' -f1 | tr -d ' ')
if [ -n "$DISCOVERY_DOMAIN" ]; then
    echo "Checking DNS for $DISCOVERY_DOMAIN:"
    nslookup $DISCOVERY_DOMAIN 2>/dev/null || echo "DNS resolution failed"
    
    echo ""
    echo "External IP of this VM:"
    curl -s --connect-timeout 10 ifconfig.me 2>/dev/null || echo "Could not determine external IP"
else
    echo "Could not determine discovery domain from Caddyfile"
fi

echo ""
echo "=== Diagnostic Summary ==="
echo "1. HTTP (port 80): $(ss -tlnp | grep -q ':80.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "2. HTTPS (port 443): $(ss -tlnp | grep -q ':443.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "3. strfry relay (port 7777): $(ss -tlnp | grep -q ':7777.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "4. strfry monitoring (port 7778): $(ss -tlnp | grep -q ':7778.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "5. Caddy service: $(systemctl is-active caddy 2>/dev/null || echo 'INACTIVE')"
echo "6. strfry service: $(systemctl is-active strfry 2>/dev/null || echo 'INACTIVE')"

echo ""
echo "=== Recommended Actions ==="
if ! ss -tlnp | grep -q ':443.*LISTEN'; then
    echo "• HTTPS (port 443) is not enabled. Run enable-https.sh after DNS is configured."
fi

if ! ss -tlnp | grep -q ':7778.*LISTEN'; then
    echo "• strfry monitoring (port 7778) is not running. Check strfry configuration and restart service."
fi

if ! systemctl is-active --quiet caddy; then
    echo "• Caddy service is not running. Check configuration and restart."
fi

if ! systemctl is-active --quiet strfry; then
    echo "• strfry service is not running. Check configuration and restart."
fi

echo ""
echo "Diagnostic complete at $(date)"
