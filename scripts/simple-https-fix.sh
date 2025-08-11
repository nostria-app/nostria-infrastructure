#!/bin/bash
# Simple Emergency HTTPS Fix for Discovery Relay
# This version avoids complex parsing and focuses on getting HTTPS working

set -e

echo "=== Simple Emergency HTTPS Fix ==="
echo "Date: $(date)"
echo ""

# Kill any hanging processes
echo "Stopping any hanging Caddy processes..."
pkill -f caddy || true
systemctl stop caddy 2>/dev/null || true
sleep 3

# Determine region from hostname
HOSTNAME=$(hostname)
echo "Hostname: $HOSTNAME"

# Extract region from hostname pattern nostria-XX-discovery
REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$REGION" ]; then
    echo "Could not auto-detect region from hostname"
    echo "Please enter the region (e.g., eu, us, af):"
    read -r REGION
fi

DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Using domain: $DISCOVERY_DOMAIN"

# Get external IP
EXTERNAL_IP=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null || echo "unknown")
echo "VM External IP: $EXTERNAL_IP"

# Test DNS
echo "Testing DNS resolution..."
RESOLVED_IP=$(dig +short $DISCOVERY_DOMAIN 2>/dev/null | tail -1)
if [ -z "$RESOLVED_IP" ]; then
    RESOLVED_IP=$(nslookup $DISCOVERY_DOMAIN 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || echo "failed")
fi
echo "DNS Resolved IP: $RESOLVED_IP"

if [ "$RESOLVED_IP" != "$EXTERNAL_IP" ] && [ "$RESOLVED_IP" != "failed" ]; then
    echo "WARNING: DNS mismatch detected!"
    echo "This may cause certificate acquisition to fail."
    echo "Please verify DNS configuration."
    echo ""
    echo "Continue anyway? (y/N):"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting. Please fix DNS first."
        exit 1
    fi
fi

# Create a simple, working HTTPS Caddyfile
echo "Creating HTTPS Caddyfile..."
cat > /etc/caddy/Caddyfile << EOF
# Simple HTTPS configuration for $DISCOVERY_DOMAIN
{
	admin localhost:2019
	storage file_system {
		root /var/lib/caddy/certificates
	}
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
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
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
	handle {
		respond "Internal monitoring" 200
	}
}
EOF

# Validate Caddyfile
echo "Validating Caddyfile..."
if ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "ERROR: Caddyfile validation failed!"
    echo "Contents of Caddyfile:"
    cat /etc/caddy/Caddyfile
    exit 1
fi
echo "✓ Caddyfile validation passed"

# Start Caddy
echo "Starting Caddy with HTTPS configuration..."
systemctl start caddy

# Wait for startup
echo "Waiting for Caddy to start..."
for i in {1..30}; do
    if systemctl is-active --quiet caddy; then
        echo "✓ Caddy started after $i seconds"
        break
    fi
    sleep 1
done

if ! systemctl is-active --quiet caddy; then
    echo "ERROR: Caddy failed to start"
    echo "Checking logs..."
    journalctl -u caddy --no-pager -n 10
    exit 1
fi

# Give Caddy time to bind to ports
sleep 10

# Test HTTPS with patience
echo ""
echo "Testing HTTPS endpoint (this may take 2-5 minutes for certificate acquisition)..."

HTTPS_SUCCESS=false
for i in {1..30}; do
    echo -n "Test $i/30: "
    
    if curl -s --connect-timeout 10 --max-time 15 https://$DISCOVERY_DOMAIN/health >/dev/null 2>&1; then
        echo "✓ HTTPS is working!"
        HTTPS_SUCCESS=true
        break
    else
        echo "✗ Not ready yet"
        
        # Show progress every 5 attempts
        if [ $((i % 5)) -eq 0 ]; then
            echo "  Certificate acquisition in progress..."
            echo "  Checking if ports are listening..."
            ss -tlnp | grep -E ":(80|443|7777)" | head -3
        fi
        
        sleep 10
    fi
done

echo ""
if [ "$HTTPS_SUCCESS" = "true" ]; then
    echo "🎉 SUCCESS: HTTPS is working for $DISCOVERY_DOMAIN"
    echo ""
    echo "Test URLs:"
    echo "  https://$DISCOVERY_DOMAIN/health"
    echo "  http://$DISCOVERY_DOMAIN/health (redirects to HTTPS)"
    echo ""
    echo "Ports status:"
    ss -tlnp | grep -E ":(80|443|7777|7778)" || echo "No matching ports found"
else
    echo "⚠ HTTPS setup completed but endpoint not responding yet"
    echo ""
    echo "Certificate acquisition can take up to 10 minutes."
    echo "Monitor with: sudo journalctl -u caddy -f"
    echo ""
    echo "Test manually: curl -v https://$DISCOVERY_DOMAIN/health"
fi

echo ""
echo "Current service status:"
echo "  Caddy: $(systemctl is-active caddy 2>/dev/null)"
echo "  strfry: $(systemctl is-active strfry 2>/dev/null)"

echo ""
echo "Emergency fix completed at $(date)"
