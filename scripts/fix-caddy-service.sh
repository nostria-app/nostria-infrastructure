#!/bin/bash
set -e

# Quick fix for Caddy service file with incorrect binary path

echo "Fixing Caddy systemd service file..."

# Determine correct Caddy binary path
CADDY_BINARY_PATH="/usr/local/bin/caddy"
if [ -f "/usr/bin/caddy" ]; then
    CADDY_BINARY_PATH="/usr/bin/caddy"
fi

echo "Using Caddy binary at: $CADDY_BINARY_PATH"

# Verify the binary exists and is executable
if [ ! -f "$CADDY_BINARY_PATH" ]; then
    echo "ERROR: Caddy binary not found at $CADDY_BINARY_PATH"
    echo "Checking common locations..."
    find /usr -name "caddy" -type f 2>/dev/null || echo "No caddy binary found"
    exit 1
fi

if [ ! -x "$CADDY_BINARY_PATH" ]; then
    echo "ERROR: Caddy binary at $CADDY_BINARY_PATH is not executable"
    chmod +x "$CADDY_BINARY_PATH"
fi

echo "Testing Caddy binary..."
if ! "$CADDY_BINARY_PATH" version >/dev/null 2>&1; then
    echo "ERROR: Caddy binary test failed"
    exit 1
fi

echo "Caddy binary test passed"

# Create corrected systemd service file
echo "Creating corrected Caddy systemd service..."
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
ExecStart=$CADDY_BINARY_PATH run --environ --config /etc/caddy/Caddyfile
ExecReload=$CADDY_BINARY_PATH reload --config /etc/caddy/Caddyfile --force
TimeoutStartSec=60s
TimeoutStopSec=5s
TimeoutReloadSec=30s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and start Caddy
echo "Reloading systemd daemon..."
systemctl daemon-reload

echo "Starting Caddy service..."
systemctl stop caddy 2>/dev/null || true
sleep 2

if systemctl start caddy; then
    echo "SUCCESS: Caddy service started successfully"
    systemctl status caddy --no-pager
else
    echo "ERROR: Caddy service failed to start"
    echo "Service status:"
    systemctl status caddy --no-pager || true
    echo "Recent logs:"
    journalctl -u caddy --no-pager -n 20 || true
    exit 1
fi

echo "Caddy service fix completed successfully!"
