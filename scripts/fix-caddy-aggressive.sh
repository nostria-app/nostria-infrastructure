#!/bin/bash
# Aggressive Caddy PKI fix script
# This script completely bypasses PKI issues and provides detailed diagnostics

set -e

echo "=== Aggressive Caddy PKI Fix Script ==="
echo "Date: $(date)"
echo "This script aggressively fixes Caddy PKI initialization errors"
echo ""

# Stop everything related to Caddy
echo "Stopping all Caddy processes..."
systemctl stop caddy 2>/dev/null || true
pkill -9 caddy 2>/dev/null || true
sleep 5

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

# Get full error details by running Caddy manually
echo ""
echo "=== Getting Full Error Details ==="
echo "Running Caddy manually to see full error message..."
if [ -f "/etc/caddy/Caddyfile" ]; then
    echo "Current Caddyfile contents:"
    echo "----------------------------------------"
    cat /etc/caddy/Caddyfile
    echo "----------------------------------------"
    echo ""
    
    echo "Running Caddy with current config to see full error:"
    timeout 10 $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 || true
    echo ""
fi

# Completely remove all Caddy data
echo "Completely removing all Caddy data directories..."
rm -rf /var/lib/caddy/* 2>/dev/null || true
rm -rf /home/caddy/.local 2>/dev/null || true
rm -rf /home/caddy/.cache 2>/dev/null || true
rm -rf /root/.local/share/caddy 2>/dev/null || true
rm -rf /root/.cache/caddy 2>/dev/null || true
rm -rf /tmp/caddy* 2>/dev/null || true

# Recreate directories with strict permissions
echo "Recreating Caddy directories..."
mkdir -p /var/lib/caddy
mkdir -p /var/log/caddy
mkdir -p /etc/caddy

# Ensure caddy user exists and fix ownership
if ! id "caddy" >/dev/null 2>&1; then
    echo "Creating caddy user..."
    useradd --system --home /var/lib/caddy --create-home --shell /usr/sbin/nologin caddy
fi

chown -R caddy:caddy /var/lib/caddy
chown -R caddy:caddy /var/log/caddy
chmod 755 /var/lib/caddy
chmod 755 /var/log/caddy

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

# Create ultra-minimal Caddyfile that avoids ALL PKI functionality
echo "Creating ultra-minimal Caddyfile (no PKI, no ACME, no certificates)..."
cat > /etc/caddy/Caddyfile << 'EOF'
# Ultra-minimal configuration - no PKI, no ACME, no certificates
{
	admin localhost:2019
	
	# Completely disable automatic HTTPS and PKI
	auto_https off
	skip_install_trust
	local_certs
	
	# Basic logging only
	log {
		output stdout
		level INFO
	}
}

# HTTP-only server - no certificates involved
:80 {
	header -Server
	
	handle /health {
		respond "Discovery Relay OK - HTTP" 200
	}
	
	handle {
		reverse_proxy localhost:7777 {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto http
		}
	}
}

# Internal monitoring on different port
:8080 {
	handle /metrics {
		reverse_proxy localhost:7778
	}
	handle /health {
		respond "Internal monitoring OK" 200
	}
}
EOF

# Test the ultra-minimal config
echo "Testing ultra-minimal Caddyfile..."
if ! $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
    echo "ERROR: Ultra-minimal Caddyfile validation failed"
    echo "This indicates a serious Caddy installation problem"
    echo "Attempting to reinstall Caddy..."
    
    # Try to reinstall Caddy
    echo "Downloading and reinstalling Caddy..."
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install --reinstall caddy -y
    
    # Update binary path
    CADDY_BINARY="/usr/bin/caddy"
    echo "Updated Caddy binary: $CADDY_BINARY"
    echo "New Caddy version: $($CADDY_BINARY version)"
    
    # Test again
    if ! $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
        echo "ERROR: Even after reinstall, Caddyfile validation fails"
        echo "This suggests a fundamental system issue"
        exit 1
    fi
fi

echo "✓ Ultra-minimal Caddyfile validation passed"

# Create systemd service with the correct binary path
echo "Creating systemd service..."
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

# Test Caddy manually first
echo "Testing Caddy startup manually..."
echo "Running: $CADDY_BINARY run --config /etc/caddy/Caddyfile"
echo "This will run for 15 seconds to test startup..."

timeout 15 sudo -u caddy $CADDY_BINARY run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

sleep 10

if kill -0 $CADDY_PID 2>/dev/null; then
    echo "✓ Caddy started successfully in manual test"
    
    # Test if it's responding
    if curl -s --connect-timeout 5 http://localhost/health >/dev/null 2>&1; then
        echo "✓ Caddy is responding to HTTP requests"
    else
        echo "⚠ Caddy started but not responding to requests yet"
    fi
    
    # Kill the test instance
    kill $CADDY_PID 2>/dev/null || true
    wait $CADDY_PID 2>/dev/null || true
    echo "✓ Manual test completed successfully"
else
    echo "✗ Caddy failed to start even in manual test"
    echo "Getting detailed error output..."
    sudo -u caddy $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 | head -20
    exit 1
fi

# Now start the service
echo "Starting Caddy service..."
systemctl daemon-reload
systemctl enable caddy
systemctl start caddy

# Wait and check status
sleep 10

if systemctl is-active --quiet caddy; then
    echo "✓ Caddy service started successfully"
    
    # Test endpoints
    echo "Testing endpoints..."
    if curl -s --connect-timeout 10 http://localhost/health | grep -q "OK"; then
        echo "✓ Local HTTP endpoint working: http://localhost/health"
    else
        echo "⚠ Local HTTP endpoint not responding"
    fi
    
    if curl -s --connect-timeout 10 http://localhost:8080/health | grep -q "OK"; then
        echo "✓ Internal monitoring working: http://localhost:8080/health"
    else
        echo "⚠ Internal monitoring not responding"
    fi
    
else
    echo "✗ Caddy service failed to start"
    echo ""
    echo "=== Service Status ==="
    systemctl status caddy --no-pager -l
    echo ""
    echo "=== Recent Logs ==="
    journalctl -u caddy --no-pager -n 30
    echo ""
    echo "=== Manual Test ==="
    echo "Running Caddy manually to see error:"
    timeout 10 sudo -u caddy $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 || true
    exit 1
fi

echo ""
echo "=== Current Status ==="
echo "Services:"
echo "  Caddy: $(systemctl is-active caddy)"
echo "  strfry: $(systemctl is-active strfry 2>/dev/null || echo 'unknown')"
echo ""
echo "Listening ports:"
ss -tlnp | grep -E ':(80|443|8080|7777|7778)'
echo ""

echo "=== Success! ==="
echo "Caddy is now running in HTTP-only mode without PKI"
echo "Domain: $DISCOVERY_DOMAIN"
echo ""
echo "Test commands:"
echo "  curl -v http://localhost/health"
echo "  curl -v http://localhost:8080/health"
echo "  curl -v http://$DISCOVERY_DOMAIN/health  # (after DNS setup)"
echo ""
echo "Monitor logs: sudo journalctl -u caddy -f"
echo ""
echo "Once DNS is configured and working, you can enable HTTPS with:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/simple-https-fix.sh | sudo bash"

echo ""
echo "Aggressive fix completed at $(date)"
