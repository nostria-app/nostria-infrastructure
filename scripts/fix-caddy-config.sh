#!/bin/bash
set -e

# Fix Caddy configuration script for existing discovery relay VMs
# This script addresses the Caddyfile formatting and permission issues

echo "Fixing Caddy configuration on existing discovery relay VM..."

# Determine Caddy binary path
CADDY_BINARY_PATH="/usr/local/bin/caddy"
if [ -f "/usr/bin/caddy" ]; then
    CADDY_BINARY_PATH="/usr/bin/caddy"
fi

echo "Using Caddy binary at: $CADDY_BINARY_PATH"

# Install missing tools if needed
echo "Installing certificate management tools..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y libnss3-tools

# Create certificate storage directory with proper permissions
echo "Setting up certificate storage..."
mkdir -p /var/lib/caddy/certificates
chown -R caddy:caddy /var/lib/caddy/certificates
chmod 700 /var/lib/caddy/certificates

# Determine the region from hostname or Azure metadata
REGION=$(hostname | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$REGION" ]; then
    REGION=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01" 2>/dev/null | sed -n 's/.*nostria-\([a-z][a-z]\)-.*/\1/p' || echo "")
fi
if [ -z "$REGION" ]; then
    REGION="eu"
    echo "Warning: Could not determine region, defaulting to 'eu'"
fi

DISCOVERY_DOMAIN="index.${REGION}.nostria.app"
echo "Configuring Caddy for domain: $DISCOVERY_DOMAIN"

# Create new Caddyfile with proper formatting
echo "Creating updated Caddyfile..."
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

# Main site configuration for $DISCOVERY_DOMAIN
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
if command -v "$CADDY_BINARY_PATH" &> /dev/null; then
    $CADDY_BINARY_PATH fmt --overwrite /etc/caddy/Caddyfile || echo "WARNING: Failed to format Caddyfile"
fi

# Validate the Caddyfile
echo "Validating Caddyfile..."
if command -v "$CADDY_BINARY_PATH" &> /dev/null; then
    if ! $CADDY_BINARY_PATH validate --config /etc/caddy/Caddyfile; then
        echo "ERROR: Caddyfile validation failed"
        exit 1
    fi
    echo "Caddyfile validation passed"
fi

# Restart Caddy to apply changes
echo "Restarting Caddy service..."
systemctl restart caddy

# Wait a moment and check status
sleep 5
if systemctl is-active --quiet caddy; then
    echo "SUCCESS: Caddy is running with the updated configuration"
    
    # Show recent logs to verify no more warnings
    echo "Recent Caddy logs:"
    journalctl -u caddy --no-pager -n 10 --since="1 minute ago"
else
    echo "ERROR: Caddy failed to start with new configuration"
    echo "Recent logs:"
    journalctl -u caddy --no-pager -n 20
    exit 1
fi

echo "Caddy configuration fix completed successfully!"
echo "The discovery relay should continue to be accessible at https://$DISCOVERY_DOMAIN"
