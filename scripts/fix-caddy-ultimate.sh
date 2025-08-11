#!/bin/bash
# Ultimate Caddy diagnostic and fix script
# This script provides comprehensive diagnostics and multiple fix approaches

set -e

echo "=== Ultimate Caddy Diagnostic and Fix ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Get domain information
HOSTNAME=$(hostname)
REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the region (e.g., eu, us, af):"
    read -r REGION
fi
DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Working with domain: $DISCOVERY_DOMAIN"
echo ""

# Step 1: Get detailed error information
echo "=== STEP 1: Detailed Error Diagnostics ==="
echo "Stopping Caddy to get clean state..."
systemctl stop caddy 2>/dev/null || true
pkill -9 caddy 2>/dev/null || true
sleep 5

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
echo "Caddy version: $($CADDY_BINARY version)"

# Check current Caddyfile
if [ -f "/etc/caddy/Caddyfile" ]; then
    echo ""
    echo "Current Caddyfile:"
    echo "----------------------------------------"
    cat /etc/caddy/Caddyfile
    echo "----------------------------------------"
else
    echo "ERROR: No Caddyfile found at /etc/caddy/Caddyfile"
    exit 1
fi

# Test current config manually to see full error
echo ""
echo "Testing current config manually for full error details:"
echo "Running: $CADDY_BINARY run --config /etc/caddy/Caddyfile"
echo "(This will timeout after 10 seconds to show error)"
timeout 10 $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 || echo "Command timed out or failed (expected)"

echo ""
echo "Getting systemd service status..."
systemctl status caddy --no-pager -l || true

echo ""
echo "Getting recent systemd logs..."
journalctl -u caddy --no-pager -n 30 || true

# Step 2: Check system prerequisites
echo ""
echo "=== STEP 2: System Prerequisites Check ==="

# Check if caddy user exists
if id "caddy" >/dev/null 2>&1; then
    echo "✓ Caddy user exists"
    echo "  User details: $(id caddy)"
else
    echo "✗ Caddy user missing - creating..."
    if ! getent group caddy > /dev/null; then
        groupadd --system caddy
    fi
    if ! getent passwd caddy > /dev/null; then
        useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy
    fi
    echo "✓ Caddy user created"
fi

# Check directories and permissions
echo "Checking directories and permissions..."
mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy /var/lib/caddy/certificates
chown -R caddy:caddy /var/lib/caddy /var/log/caddy
chmod 755 /var/lib/caddy /var/log/caddy
chmod 700 /var/lib/caddy/certificates

echo "Directory ownership:"
ls -la /var/lib/caddy/
ls -la /var/log/caddy/

# Check capabilities
echo ""
echo "Checking Caddy capabilities..."
CURRENT_CAPS=$(getcap $CADDY_BINARY 2>/dev/null || echo "none")
echo "Current capabilities: $CURRENT_CAPS"

if [[ "$CURRENT_CAPS" != *"cap_net_bind_service"* ]]; then
    echo "Setting CAP_NET_BIND_SERVICE capability..."
    setcap 'cap_net_bind_service=+ep' $CADDY_BINARY
    echo "New capabilities: $(getcap $CADDY_BINARY)"
else
    echo "✓ Capabilities already set correctly"
fi

# Check if ports are available
echo ""
echo "Checking port availability..."
if ss -tlnp | grep -q ':80.*LISTEN'; then
    echo "⚠ Port 80 is already in use:"
    ss -tlnp | grep ':80.*LISTEN'
    echo "Killing processes using port 80..."
    fuser -k 80/tcp 2>/dev/null || true
    sleep 2
fi

if ss -tlnp | grep -q ':443.*LISTEN'; then
    echo "⚠ Port 443 is already in use:"
    ss -tlnp | grep ':443.*LISTEN'
    echo "Killing processes using port 443..."
    fuser -k 443/tcp 2>/dev/null || true
    sleep 2
fi

# Step 3: Create minimal working config
echo ""
echo "=== STEP 3: Creating Minimal Working Configuration ==="

# Create the most basic possible Caddyfile that should work
cat > /etc/caddy/Caddyfile << EOF
# Ultra-minimal Caddy configuration
{
	admin localhost:2019
	auto_https off
	local_certs
}

# HTTP-only configuration
:80 {
	respond "Caddy is working!" 200
}

# Test localhost
localhost:8080 {
	respond "Localhost test" 200
}
EOF

echo "Created minimal test configuration:"
cat /etc/caddy/Caddyfile

# Test the minimal config
echo ""
echo "Testing minimal configuration..."
if ! $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
    echo "✗ Even minimal config validation failed - Caddy installation is broken"
    echo "Attempting to reinstall Caddy..."
    
    # Remove current installation
    rm -f $CADDY_BINARY
    
    # Reinstall via apt
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt update
    apt install --reinstall caddy -y
    
    # Update binary path
    CADDY_BINARY="/usr/bin/caddy"
    echo "Reinstalled Caddy at: $CADDY_BINARY"
    
    # Set capabilities again
    setcap 'cap_net_bind_service=+ep' $CADDY_BINARY
    
    # Test again
    if ! $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
        echo "✗ Still failing after reinstall - system issue"
        exit 1
    fi
fi

echo "✓ Minimal config validation passed"

# Test manual startup with minimal config
echo ""
echo "Testing manual startup with minimal config..."
timeout 15 $CADDY_BINARY run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

sleep 10

if kill -0 $CADDY_PID 2>/dev/null; then
    echo "✓ Minimal config starts successfully"
    
    # Test if it responds
    if curl -s --connect-timeout 5 http://localhost/; then
        echo "✓ Minimal HTTP server responds"
    else
        echo "⚠ Starts but doesn't respond to HTTP"
    fi
    
    # Kill test instance
    kill $CADDY_PID 2>/dev/null || true
    wait $CADDY_PID 2>/dev/null || true
else
    echo "✗ Even minimal config fails to start"
    echo "Manual test output:"
    $CADDY_BINARY run --config /etc/caddy/Caddyfile 2>&1 | head -20
    exit 1
fi

# Step 4: Create proper systemd service
echo ""
echo "=== STEP 4: Creating Proper Systemd Service ==="

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

systemctl daemon-reload

# Test service start with minimal config
echo "Testing systemd service start with minimal config..."
systemctl start caddy

sleep 5

if systemctl is-active --quiet caddy; then
    echo "✓ Systemd service starts successfully with minimal config"
    
    # Now create the real configuration
    echo ""
    echo "=== STEP 5: Creating Production Configuration ==="
    
    cat > /etc/caddy/Caddyfile << EOF
# Production configuration for $DISCOVERY_DOMAIN
{
	admin localhost:2019
	
	# Enable automatic HTTPS
	# Remove auto_https off to enable certificate acquisition
	
	# Storage for certificates
	storage file_system {
		root /var/lib/caddy/certificates
	}
	
	# Logging
	log {
		output file /var/log/caddy/caddy.log
		level INFO
	}
}

# HTTPS site
$DISCOVERY_DOMAIN {
	header {
		X-Frame-Options DENY
		X-Content-Type-Options nosniff
		Strict-Transport-Security "max-age=31536000"
		-Server
	}

	handle /health {
		respond "OK" 200
	}

	handle {
		reverse_proxy localhost:7777 {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
		}
	}

	log {
		output file /var/log/caddy/discovery-access.log
	}
}

# HTTP to HTTPS redirect
http://$DISCOVERY_DOMAIN {
	redir https://{host}{uri} permanent
}

# Internal monitoring
localhost:8080 {
	handle /metrics {
		reverse_proxy localhost:7778
	}
	handle /health {
		respond "Discovery Relay OK" 200
	}
}
EOF

    echo "Created production configuration"
    
    # Validate production config
    if $CADDY_BINARY validate --config /etc/caddy/Caddyfile; then
        echo "✓ Production config validates"
        
        # Reload with production config
        echo "Reloading with production configuration..."
        if systemctl reload caddy; then
            echo "✓ Successfully reloaded with HTTPS configuration"
            
            # Wait for certificate acquisition
            echo "Waiting for certificate acquisition (up to 60 seconds)..."
            for i in {1..60}; do
                if curl -s --connect-timeout 5 https://$DISCOVERY_DOMAIN/health >/dev/null 2>&1; then
                    echo "✓ HTTPS is working! (after ${i} seconds)"
                    break
                fi
                sleep 1
                if [ $i -eq 60 ]; then
                    echo "⚠ HTTPS not responding after 60 seconds, but service is running"
                fi
            done
        else
            echo "✗ Failed to reload with HTTPS config"
            echo "Systemd logs:"
            journalctl -u caddy --no-pager -n 20
        fi
    else
        echo "✗ Production config validation failed"
        cat /etc/caddy/Caddyfile
    fi
    
else
    echo "✗ Systemd service failed to start even with minimal config"
    echo "Service status:"
    systemctl status caddy --no-pager -l
    echo "Systemd logs:"
    journalctl -u caddy --no-pager -n 20
    exit 1
fi

echo ""
echo "=== Final Status ==="
echo "Service status: $(systemctl is-active caddy)"
echo "Listening ports:"
ss -tlnp | grep -E ':(80|443|8080)'

echo ""
echo "Test commands:"
echo "  curl -v http://$DISCOVERY_DOMAIN/health"
echo "  curl -v https://$DISCOVERY_DOMAIN/health"
echo "  curl -v http://localhost:8080/health"

echo ""
echo "Monitor logs: sudo journalctl -u caddy -f"
echo ""
echo "Ultimate diagnostic completed at $(date)"
