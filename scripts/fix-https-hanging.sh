#!/bin/bash
# Emergency fix for hanging HTTPS enable script
# Run this if enable-https.sh hangs at "Reloading Caddy with HTTPS configuration..."

set -e

echo "=== Emergency HTTPS Fix Script ==="
echo "Date: $(date)"
echo "This script fixes hanging HTTPS enablement issues"
echo ""

# Kill any hanging Caddy processes
echo "Stopping any hanging Caddy processes..."
pkill -f caddy || true
systemctl stop caddy 2>/dev/null || true
sleep 3

# Check if we have a backup Caddyfile
if [ ! -f "/etc/caddy/Caddyfile.http.backup" ]; then
    echo "ERROR: No HTTP backup found. Cannot safely proceed."
    echo "Please restore your Caddyfile manually and try again."
    exit 1
fi

# Get the discovery domain
DISCOVERY_DOMAIN=$(grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" /etc/caddy/Caddyfile.http.backup | head -1 | cut -d':' -f1 | tr -d ' ')
if [ -z "$DISCOVERY_DOMAIN" ]; then
    echo "ERROR: Could not determine discovery domain"
    exit 1
fi

echo "Discovery domain: $DISCOVERY_DOMAIN"

# Test DNS resolution
echo "Testing DNS resolution..."
EXTERNAL_IP=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null)
RESOLVED_IP=$(nslookup $DISCOVERY_DOMAIN 2>/dev/null | grep -A1 "Name:" | grep "Address:" | cut -d' ' -f2 | tail -1)

echo "VM External IP: $EXTERNAL_IP"
echo "DNS Resolved IP: $RESOLVED_IP"

if [ "$RESOLVED_IP" != "$EXTERNAL_IP" ]; then
    echo "WARNING: DNS mismatch! This may cause certificate acquisition to fail."
    echo "Please ensure DNS is correctly configured before enabling HTTPS."
fi

# Create a simplified HTTPS Caddyfile without timeouts
echo "Creating optimized HTTPS Caddyfile..."
cat > /etc/caddy/Caddyfile << EOF
# Global options (simplified for reliability)
{
	admin localhost:2019
	
	# Set storage location
	storage file_system {
		root /var/lib/caddy/certificates
	}
	
	# Basic logging
	log {
		output file /var/log/caddy/caddy.log
		level INFO
	}
	
	# Use staging server for testing (comment out for production)
	# acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}

# HTTPS site
$DISCOVERY_DOMAIN {
	# Basic security headers
	header {
		X-Frame-Options DENY
		X-Content-Type-Options nosniff
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		-Server
	}
	
	# Health endpoint
	handle /health {
		respond "OK" 200
	}
	
	# Proxy to strfry
	handle {
		reverse_proxy localhost:7777 {
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
		}
	}
	
	# Access logging
	log {
		output file /var/log/caddy/discovery-access.log
	}
}

# HTTP redirect
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

# Validate new Caddyfile
echo "Validating new Caddyfile..."
if ! caddy validate --config /etc/caddy/Caddyfile; then
    echo "ERROR: Caddyfile validation failed"
    echo "Restoring HTTP configuration..."
    cp /etc/caddy/Caddyfile.http.backup /etc/caddy/Caddyfile
    exit 1
fi

# Start Caddy in background with progress monitoring
echo "Starting Caddy with HTTPS configuration..."
echo "This will take 30-120 seconds for certificate acquisition..."

# Start Caddy and monitor logs in background
systemctl start caddy &
CADDY_PID=$!

# Monitor startup with live feedback
echo "Monitoring Caddy startup..."
for i in {1..120}; do
    if systemctl is-active --quiet caddy; then
        echo "✓ Caddy service is active (after $i seconds)"
        break
    fi
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "  Still starting... ($i/120 seconds)"
    fi
    
    sleep 1
done

# Wait for Caddy to be truly ready
sleep 10

# Test HTTPS with progress reporting
echo ""
echo "Testing HTTPS endpoint..."
HTTPS_SUCCESS=false

for i in {1..20}; do
    echo -n "Test $i/20: "
    
    if curl -s --connect-timeout 10 --max-time 20 https://$DISCOVERY_DOMAIN/health > /dev/null 2>&1; then
        echo "✓ HTTPS is working!"
        HTTPS_SUCCESS=true
        break
    else
        echo "✗ Not ready yet"
        
        # Show periodic status updates
        if [ $((i % 5)) -eq 0 ]; then
            echo "  Certificate acquisition in progress..."
            if journalctl -u caddy --since "1 minute ago" | grep -q "certificate"; then
                echo "  Found certificate activity in logs"
            fi
        fi
        
        sleep 15
    fi
done

# Final status
echo ""
if [ "$HTTPS_SUCCESS" = "true" ]; then
    echo "🎉 SUCCESS: HTTPS is now working for $DISCOVERY_DOMAIN"
    echo ""
    echo "Test URLs:"
    echo "  https://$DISCOVERY_DOMAIN/health"
    echo "  http://$DISCOVERY_DOMAIN/health (should redirect to HTTPS)"
    echo ""
    echo "Monitoring:"
    echo "  http://localhost:8080/health"
else
    echo "⚠ HTTPS setup completed but endpoint not yet responding"
    echo ""
    echo "This is normal - certificate acquisition can take up to 10 minutes."
    echo ""
    echo "Monitor progress:"
    echo "  sudo journalctl -u caddy -f"
    echo ""
    echo "Check manually:"
    echo "  curl -v https://$DISCOVERY_DOMAIN/health"
    echo ""
    echo "If problems persist after 10 minutes, restore HTTP:"
    echo "  sudo cp /etc/caddy/Caddyfile.http.backup /etc/caddy/Caddyfile"
    echo "  sudo systemctl restart caddy"
fi

echo ""
echo "Current service status:"
echo "  Caddy: $(systemctl is-active caddy 2>/dev/null || echo 'INACTIVE')"
echo "  strfry: $(systemctl is-active strfry 2>/dev/null || echo 'INACTIVE')"
echo ""
echo "Current listening ports:"
echo "  Port 80: $(ss -tlnp | grep -q ':80.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"
echo "  Port 443: $(ss -tlnp | grep -q ':443.*LISTEN' && echo 'LISTENING' || echo 'NOT LISTENING')"

echo ""
echo "Fix script completed at $(date)"
