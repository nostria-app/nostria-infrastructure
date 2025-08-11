#!/bin/bash
# Fix Caddy PKI initialization errors
# This script fixes common Caddy startup issues related to PKI/certificate management

set -e

echo "=== Caddy PKI Error Fix Script ==="
echo "Date: $(date)"
echo "This script fixes Caddy PKI initialization errors"
echo ""

# Stop Caddy service
echo "Stopping Caddy service..."
systemctl stop caddy 2>/dev/null || true
pkill -f caddy 2>/dev/null || true
sleep 3

# Check Caddy installation
echo "Checking Caddy installation..."
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
echo "Caddy version: $($CADDY_BINARY version)"

# Clean up any corrupted certificate directories
echo "Cleaning up certificate directories..."
rm -rf /var/lib/caddy/certificates/* 2>/dev/null || true
rm -rf /var/lib/caddy/.local/share/caddy/* 2>/dev/null || true
rm -rf /root/.local/share/caddy/* 2>/dev/null || true

# Recreate certificate directories with proper permissions
echo "Recreating certificate directories..."
mkdir -p /var/lib/caddy/certificates
mkdir -p /var/lib/caddy/.local/share/caddy
chown -R caddy:caddy /var/lib/caddy
chmod -R 700 /var/lib/caddy/certificates
chmod -R 755 /var/lib/caddy

# Fix any permission issues with Caddy user home directory
echo "Fixing Caddy user permissions..."
if [ -d "/var/lib/caddy" ]; then
    chown caddy:caddy /var/lib/caddy
    chmod 755 /var/lib/caddy
fi

# Get region and domain
HOSTNAME=$(hostname)
REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the region (e.g., eu, us, af):"
    read -r REGION
fi

DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Configuring for domain: $DISCOVERY_DOMAIN"

# Create a minimal working Caddyfile for initial testing
echo "Creating minimal Caddyfile for testing..."
cat > /etc/caddy/Caddyfile << EOF
# Minimal configuration to test Caddy startup
{
	admin localhost:2019
	
	# Use simple file storage
	storage file_system {
		root /var/lib/caddy/certificates
	}
	
	# Disable automatic HTTPS initially to avoid PKI issues
	auto_https off
	
	# Basic logging
	log {
		output file /var/log/caddy/caddy.log
		level INFO
	}
}

# HTTP-only configuration for initial testing
$DISCOVERY_DOMAIN:80 {
	header -Server
	
	handle /health {
		respond "OK" 200
	}
	
	handle {
		reverse_proxy localhost:7777 {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
		}
	}
	
	log {
		output file /var/log/caddy/discovery-access.log
	}
}

# Internal monitoring
localhost:8080 {
	handle /metrics {
		reverse_proxy localhost:7778
	}
	handle /health {
		respond "Discovery Relay OK" 200
	}
	handle {
		respond "Internal monitoring" 200
	}
}
EOF

# Validate the minimal Caddyfile
echo "Validating minimal Caddyfile..."
if ! $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
    echo "ERROR: Even minimal Caddyfile validation failed"
    echo "This suggests a deeper Caddy installation issue"
    exit 1
fi
echo "✓ Minimal Caddyfile validation passed"

# Test Caddy startup with minimal config
echo "Testing Caddy startup with minimal configuration..."
timeout 30 $CADDY_BINARY run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

# Wait for Caddy to start
sleep 10

# Check if Caddy started successfully
if kill -0 $CADDY_PID 2>/dev/null; then
    echo "✓ Caddy started successfully with minimal config"
    
    # Test if it's responding
    if curl -s --connect-timeout 5 http://localhost/health >/dev/null 2>&1; then
        echo "✓ Caddy is responding to HTTP requests"
    else
        echo "⚠ Caddy started but not responding to requests"
    fi
    
    # Stop the test instance
    kill $CADDY_PID 2>/dev/null || true
    wait $CADDY_PID 2>/dev/null || true
else
    echo "✗ Caddy failed to start even with minimal config"
    echo "Checking for specific error messages..."
    $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 | head -10
    exit 1
fi

# Update systemd service to use absolute path
echo "Updating systemd service file..."
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

# Reload systemd and start Caddy service
echo "Starting Caddy service..."
systemctl daemon-reload
systemctl enable caddy
systemctl start caddy

# Wait for service to start
sleep 10

# Check service status
if systemctl is-active --quiet caddy; then
    echo "✓ Caddy service started successfully"
    
    # Test HTTP endpoint
    echo "Testing HTTP endpoint..."
    if curl -s --connect-timeout 10 http://$DISCOVERY_DOMAIN/health >/dev/null 2>&1; then
        echo "✓ HTTP endpoint is working: http://$DISCOVERY_DOMAIN/health"
    elif curl -s --connect-timeout 10 http://localhost/health >/dev/null 2>&1; then
        echo "✓ Local HTTP endpoint is working: http://localhost/health"
        echo "⚠ External domain may need DNS configuration"
    else
        echo "⚠ HTTP endpoint not responding yet"
    fi
    
else
    echo "✗ Caddy service failed to start"
    echo "Service status:"
    systemctl status caddy --no-pager -l
    echo ""
    echo "Recent logs:"
    journalctl -u caddy --no-pager -n 20
    exit 1
fi

echo ""
echo "=== Current Status ==="
echo "Services:"
echo "  Caddy: $(systemctl is-active caddy)"
echo "  strfry: $(systemctl is-active strfry 2>/dev/null || echo 'unknown')"
echo ""
echo "Listening ports:"
echo "  Port 80: $(ss -tlnp | grep -q ':80.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "  Port 443: $(ss -tlnp | grep -q ':443.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo ""

echo "=== Next Steps ==="
echo "1. Caddy is now running in HTTP-only mode"
echo "2. Configure DNS to point $DISCOVERY_DOMAIN to this server"
echo "3. Once DNS is working, enable HTTPS with:"
echo "   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/simple-https-fix.sh | sudo bash"
echo ""
echo "Monitor Caddy logs: sudo journalctl -u caddy -f"
echo "Test HTTP health: curl -v http://$DISCOVERY_DOMAIN/health"

echo ""
echo "PKI fix completed at $(date)"
