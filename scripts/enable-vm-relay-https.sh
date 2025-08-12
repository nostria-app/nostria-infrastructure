#!/bin/bash

# VM Relay HTTPS Enablement Script
# This script configures Caddy to use HTTPS for VM relay domains like ribo.[region].nostria.app

set -e

echo "=== VM Relay HTTPS Configuration ==="
echo "Date: $(date)"

# Function to get the relay domain based on VM hostname
get_relay_domain() {
    local hostname=$(hostname)
    
    # Extract region and relay name from hostname pattern: nostria-[region]-[relay]-vm
    if [[ $hostname =~ nostria-([a-z]+)-([a-z]+)-vm ]]; then
        local region="${BASH_REMATCH[1]}"
        local relay="${BASH_REMATCH[2]}"
        echo "$relay.$region.nostria.app"
    else
        echo "ERROR: Cannot determine relay domain from hostname: $hostname" >&2
        echo "Expected format: nostria-[region]-[relay]-vm" >&2
        exit 1
    fi
}

# Get the relay domain
echo "Current hostname: $(hostname)"
RELAY_DOMAIN=$(get_relay_domain)
echo "Configuring HTTPS for domain: $RELAY_DOMAIN"

# Check if Caddy is running
if ! systemctl is-active caddy &>/dev/null; then
    echo "ERROR: Caddy service is not running"
    echo "Please ensure Caddy is installed and running first"
    exit 1
fi

# Check if strfry is running
if ! systemctl is-active strfry &>/dev/null; then
    echo "ERROR: strfry service is not running"
    echo "Please ensure strfry is installed and running first"
    exit 1
fi

# Backup current Caddyfile
echo "Backing up current Caddyfile..."
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup.$(date +%Y%m%d-%H%M%S)

# Create new Caddyfile with HTTPS configuration
echo "Creating new Caddyfile with HTTPS configuration..."
sudo tee /etc/caddy/Caddyfile > /dev/null << EOF
{
    admin off
    email admin@nostria.app
}

$RELAY_DOMAIN {
    reverse_proxy 127.0.0.1:7777
    
    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Accept, Accept-Encoding, Sec-WebSocket-Protocol, Sec-WebSocket-Extensions, Sec-WebSocket-Key, Sec-WebSocket-Version, Upgrade, Connection"
    }
    
    # Handle WebSocket upgrade
    @websocket {
        header Connection upgrade
        header Upgrade websocket
    }
    reverse_proxy @websocket 127.0.0.1:7777
    
    # Health check endpoint
    respond /health 200 {
        body "VM Relay is healthy"
    }
    
    # NIP-11 relay info
    @nip11 {
        header Accept application/nostr+json
    }
    header @nip11 Content-Type application/json
    respond @nip11 200 {
        body "{
            \"name\": \"$RELAY_DOMAIN\",
            \"description\": \"High-performance VM-based Nostr relay powered by strfry\",
            \"pubkey\": \"\",
            \"contact\": \"admin@nostria.app\",
            \"supported_nips\": [1, 2, 4, 9, 11, 12, 15, 16, 20, 22, 28, 33, 40],
            \"software\": \"strfry\",
            \"version\": \"0.9.6\"
        }"
    }
}

# Redirect HTTP to HTTPS
http://$RELAY_DOMAIN {
    redir https://{host}{uri} permanent
}
EOF

echo "Caddyfile updated. Testing configuration..."

# Test Caddy configuration
if sudo caddy validate --config /etc/caddy/Caddyfile; then
    echo "✅ Caddy configuration is valid"
else
    echo "❌ Caddy configuration is invalid. Restoring backup..."
    sudo cp /etc/caddy/Caddyfile.backup.* /etc/caddy/Caddyfile
    exit 1
fi

# Reload Caddy
echo "Reloading Caddy with HTTPS configuration..."
sudo systemctl reload caddy

# Wait for certificate acquisition
echo "Waiting for TLS certificate acquisition..."
sleep 10

# Check if HTTPS is working
echo "Testing HTTPS connectivity..."
for attempt in {1..6}; do
    echo "Attempt $attempt/6: Testing HTTPS..."
    if curl -s --max-time 10 --connect-timeout 5 "https://$RELAY_DOMAIN/health" > /dev/null; then
        echo "✅ HTTPS is working!"
        break
    elif [ $attempt -eq 6 ]; then
        echo "❌ HTTPS test failed after 6 attempts"
        echo "Certificate acquisition may still be in progress..."
    else
        echo "Waiting 10 seconds before retry..."
        sleep 10
    fi
done

# Show Caddy status and logs
echo ""
echo "=== Caddy Status ==="
sudo systemctl status caddy --no-pager -l

echo ""
echo "=== Recent Caddy Logs ==="
sudo journalctl -u caddy --no-pager -l -n 20

echo ""
echo "=== Configuration Summary ==="
echo "Domain: $RELAY_DOMAIN"
echo "HTTP to HTTPS redirect: ✅ Enabled"
echo "CORS headers: ✅ Enabled"
echo "WebSocket support: ✅ Enabled"
echo "Health check: ✅ Available at https://$RELAY_DOMAIN/health"
echo "NIP-11 info: ✅ Available with Accept: application/nostr+json"

echo ""
echo "=== Next Steps ==="
echo "1. Ensure DNS record points $RELAY_DOMAIN to this VM's public IP"
echo "2. Wait for DNS propagation (5-30 minutes)"
echo "3. Test the relay: curl -v https://$RELAY_DOMAIN/health"
echo "4. Test WebSocket: Use a nostr client to connect to wss://$RELAY_DOMAIN"

echo ""
echo "=== Troubleshooting ==="
echo "If HTTPS doesn't work immediately:"
echo "- Check DNS: nslookup $RELAY_DOMAIN"
echo "- Monitor logs: sudo journalctl -u caddy -f"
echo "- Check certificate: sudo caddy list-certificates"
echo "- Manual reload: sudo systemctl reload caddy"

echo "HTTPS configuration completed at $(date)"
