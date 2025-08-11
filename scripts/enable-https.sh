#!/bin/bash
set -e

# Enable HTTPS on discovery relay after DNS is configured
# Run this script after setting up DNS records pointing to the VM's public IP

echo "Enabling HTTPS for discovery relay..."

# Determine Caddy binary path
CADDY_BINARY_PATH="/usr/local/bin/caddy"
if [ -f "/usr/bin/caddy" ]; then
    CADDY_BINARY_PATH="/usr/bin/caddy"
fi

echo "Using Caddy binary at: $CADDY_BINARY_PATH"

# Determine the region from hostname or Azure metadata
REGION=$(hostname | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$REGION" ]; then
    REGION=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01" 2>/dev/null | sed -n 's/.*nostria-\([a-z][a-z]\)-.*/\1/p' || echo "")
fi
if [ -z "$REGION" ]; then
    REGION="eu"
    echo "Warning: Could not determine region, defaulting to 'eu'"
fi

DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Enabling HTTPS for domain: $DISCOVERY_DOMAIN"

# Test DNS resolution first
echo "Testing DNS resolution for $DISCOVERY_DOMAIN..."
if ! nslookup $DISCOVERY_DOMAIN >/dev/null 2>&1; then
    echo "WARNING: DNS resolution failed for $DISCOVERY_DOMAIN"
    echo "Make sure DNS records are properly configured before enabling HTTPS"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting HTTPS enablement"
        exit 1
    fi
fi

# Backup current HTTP configuration
echo "Backing up current HTTP configuration..."
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.http.backup

# Create HTTPS Caddyfile
echo "Creating HTTPS Caddyfile..."
cat > /etc/caddy/Caddyfile << EOF
# Global options
{
	# Enable admin API on localhost only
	admin localhost:2019
	
	# Set storage location for certificates (writable by caddy user)
	storage file_system {
		root /var/lib/caddy/certificates
	}
	
	# Log settings
	log {
		output file /var/log/caddy/caddy.log
		level INFO
	}
}

# Main site configuration for $DISCOVERY_DOMAIN with HTTPS
$DISCOVERY_DOMAIN {
	# Enable automatic HTTPS
	tls {
		protocols tls1.2 tls1.3
	}
	
	# Security headers
	header {
		# Enable HSTS
		Strict-Transport-Security max-age=31536000;
		
		# Prevent clickjacking
		X-Frame-Options DENY
		
		# Prevent MIME sniffing
		X-Content-Type-Options nosniff
		
		# XSS protection
		X-XSS-Protection "1; mode=block"
		
		# Referrer policy
		Referrer-Policy strict-origin-when-cross-origin
		
		# Remove server information
		-Server
	}
	
	# Health check endpoint
	handle /health {
		respond "OK" 200
	}
	
	# WebSocket proxy for strfry nostr relay (catch-all for other paths)
	handle {
		reverse_proxy localhost:7777 {
			# WebSocket support
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
			header_up X-Forwarded-Host {host}
		}
	}
	
	# Access logging
	log {
		output file /var/log/caddy/discovery-access.log
		format json
	}
	
	# Error handling
	handle_errors {
		respond "Service temporarily unavailable" 503
	}
}

# Monitoring endpoint (internal access only via localhost)
localhost:8080 {
	# Strfry monitoring endpoint
	handle /metrics {
		reverse_proxy localhost:7778
	}
	
	# Basic health check
	handle /health {
		respond "Discovery Relay OK" 200
	}
	
	# System stats
	handle /stats {
		respond "Discovery relay statistics endpoint" 200
	}
	
	# Default response
	handle {
		respond "Internal monitoring interface" 200
	}
}
EOF

# Format the Caddyfile
echo "Formatting Caddyfile..."
$CADDY_BINARY_PATH fmt --overwrite /etc/caddy/Caddyfile

# Validate the Caddyfile
echo "Validating Caddyfile..."
if ! $CADDY_BINARY_PATH validate --config /etc/caddy/Caddyfile; then
    echo "ERROR: HTTPS Caddyfile validation failed"
    echo "Restoring HTTP configuration..."
    cp /etc/caddy/Caddyfile.http.backup /etc/caddy/Caddyfile
    exit 1
fi

echo "Caddyfile validation passed"

# Restart Caddy with new HTTPS configuration (reload can hang during HTTP->HTTPS transition)
echo "Restarting Caddy with HTTPS configuration..."
systemctl stop caddy
sleep 3

# Start Caddy with timeout protection to prevent hanging
timeout 60 systemctl start caddy &
CADDY_START_PID=$!

# Wait for Caddy to start with timeout
echo "Waiting for Caddy to start (timeout: 60 seconds)..."
CADDY_STARTED=false
for i in {1..60}; do
    if systemctl is-active --quiet caddy; then
        CADDY_STARTED=true
        echo "Caddy started successfully after $i seconds"
        break
    fi
    sleep 1
done

# Kill the start command if it's still running
kill $CADDY_START_PID 2>/dev/null || true

if [ "$CADDY_STARTED" = "false" ]; then
    echo "ERROR: Caddy failed to start with HTTPS configuration within 60 seconds"
    echo "Restoring HTTP configuration..."
    cp /etc/caddy/Caddyfile.http.backup /etc/caddy/Caddyfile
    systemctl stop caddy 2>/dev/null || true
    sleep 2
    systemctl start caddy
    exit 1
fi

# Wait for Caddy to start and obtain certificates
echo "Waiting for HTTPS certificate acquisition (this may take up to 2 minutes)..."
sleep 30

# Test HTTPS endpoint
for i in {1..12}; do
    if curl -s --connect-timeout 10 https://$DISCOVERY_DOMAIN/health >/dev/null 2>&1; then
        echo "SUCCESS: HTTPS is working for $DISCOVERY_DOMAIN"
        echo "You can now access the discovery relay at: https://$DISCOVERY_DOMAIN"
        echo "HTTP access will automatically redirect to HTTPS"
        exit 0
    fi
    echo "Attempt $i/12: HTTPS not ready yet, waiting 10 seconds..."
    sleep 10
done

echo "WARNING: HTTPS may not be fully working yet"
echo "Check Caddy logs for details:"
echo "  journalctl -u caddy -f"
echo ""
echo "You can test manually with:"
echo "  curl -v https://$DISCOVERY_DOMAIN/health"
echo ""
echo "If there are issues, you can restore HTTP mode with:"
echo "  sudo cp /etc/caddy/Caddyfile.http.backup /etc/caddy/Caddyfile"
echo "  sudo systemctl reload caddy"
