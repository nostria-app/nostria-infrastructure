#!/bin/bash
# Quick fix for Caddy port binding permission issue

set -e

echo "=== Caddy Port Binding Fix ==="
echo "Date: $(date)"
echo "Fixing Caddy permission to bind to port 80"
echo ""

# Stop Caddy
echo "Stopping Caddy..."
systemctl stop caddy 2>/dev/null || true
pkill -f caddy 2>/dev/null || true
sleep 2

# Find Caddy binary
CADDY_BINARY=""
if [ -f "/usr/local/bin/caddy" ]; then
    CADDY_BINARY="/usr/local/bin/caddy"
elif [ -f "/usr/bin/caddy" ]; then
    CADDY_BINARY="/usr/bin/caddy"
else
    echo "ERROR: Caddy binary not found"
    exit 1
fi

echo "Using Caddy binary: $CADDY_BINARY"

# Give Caddy the capability to bind to privileged ports
echo "Setting CAP_NET_BIND_SERVICE capability..."
setcap 'cap_net_bind_service=+ep' $CADDY_BINARY

# Verify the capability was set
echo "Verifying capability:"
getcap $CADDY_BINARY

# Update systemd service to ensure capabilities are preserved
echo "Updating systemd service to run as caddy user..."
cat > /etc/systemd/system/caddy.service << EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=$CADDY_BINARY run --environ --config /etc/caddy/Caddyfile
ExecReload=$CADDY_BINARY reload --config /etc/caddy/Caddyfile --force
TimeoutStartSec=30s
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "Reloading systemd..."
systemctl daemon-reload

# Start Caddy
echo "Starting Caddy service..."
systemctl start caddy

# Wait and check
sleep 5

if systemctl is-active --quiet caddy; then
    echo "✓ Caddy started successfully!"
    
    # Check if port 80 is listening
    if ss -tlnp | grep -q ':80.*LISTEN'; then
        echo "✓ Port 80 is listening"
    else
        echo "⚠ Port 80 not listening yet"
    fi
    
    # Test endpoint
    if curl -s --connect-timeout 5 http://localhost/health >/dev/null 2>&1; then
        echo "✓ HTTP endpoint responding"
    else
        echo "⚠ HTTP endpoint not responding yet"
    fi
    
else
    echo "✗ Caddy failed to start"
    echo "Service status:"
    systemctl status caddy --no-pager -l
    echo ""
    echo "Recent logs:"
    journalctl -u caddy --no-pager -n 10
fi

echo ""
echo "Port binding fix completed at $(date)"
