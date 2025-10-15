#!/bin/bash
# Setup script for strfry router sync configuration
# This configures two-way sync with purplepag.es and one-way sync from damus.io and primal.net
# Only syncs event kinds 3 (contact lists) and 10002 (relay lists)

set -e

echo "=== Strfry Router Setup for Discovery Relay ==="
echo "Timestamp: $(date)"

# Check if strfry is installed
if ! command -v strfry &> /dev/null; then
    echo "ERROR: strfry binary not found. Please install strfry first."
    exit 1
fi

# Check if strfry user exists
if ! id strfry &>/dev/null; then
    echo "ERROR: strfry user does not exist. Please run the main discovery VM setup first."
    exit 1
fi

# Create router config directory
echo "Creating router configuration directory..."
mkdir -p /etc/strfry

# Create the router configuration file
echo "Creating strfry router configuration..."

# Determine current region from hostname to avoid self-sync
HOSTNAME=$(hostname)
CURRENT_REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$CURRENT_REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the current region (eu, us, af):"
    read -r CURRENT_REGION
fi

echo "Detected current region: $CURRENT_REGION"
echo "Configuring sync with other Discovery Relays..."

# Start building the configuration file
cat > /etc/strfry/strfry-router.conf << 'EOF'
# strfry router configuration for syncing event kinds 3 and 10002
# This configuration handles:
# - Two-way sync with other Nostria Discovery Relays
# - Two-way sync with purplepag.es
# - One-way sync (down only) from relay.damus.io and relay.primal.net

# Connection timeout in seconds
connectionTimeout = 20

# Logging configuration
logLevel = "info"

# Stream configurations
streams {
EOF

# Add two-way sync with other Nostria Discovery Relays (excluding current region)
if [ "$CURRENT_REGION" != "eu" ]; then
    echo "Adding EU Discovery Relay sync configuration..."
    cat >> /etc/strfry/strfry-router.conf << 'EOF'
    
    # Two-way sync with Nostria EU Discovery Relay
    nostria_eu {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.eu.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

if [ "$CURRENT_REGION" != "us" ]; then
    echo "Adding US Discovery Relay sync configuration..."
    cat >> /etc/strfry/strfry-router.conf << 'EOF'
    
    # Two-way sync with Nostria US Discovery Relay
    nostria_us {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.us.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

if [ "$CURRENT_REGION" != "af" ]; then
    echo "Adding AF Discovery Relay sync configuration..."
    cat >> /etc/strfry/strfry-router.conf << 'EOF'
    
    # Two-way sync with Nostria AF Discovery Relay
    nostria_af {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://discovery.af.nostria.app/"
        ]
        
        # Reconnect settings for reliability
        reconnectDelaySeconds = 30
    }
EOF
fi

# Add the rest of the configuration (external relays)
echo "Adding external relay sync configurations..."
cat >> /etc/strfry/strfry-router.conf << 'EOF'
    
    # Two-way sync with purplepag.es
    # Sync contact lists (kind 3) and relay lists (kind 10002) bidirectionally
    purplepages {
        dir = "both"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://purplepag.es/"
        ]
        
        # Optional: Add plugin for additional filtering if needed
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
        # pluginUp = "/etc/strfry/plugins/validate-events.js"
    }
    
    # Two-way sync with Coracle indexer
    # Sync relay lists (kind 10002) bidirectionally
    # Note: Coracle only supports kind 10002, not kind 3
    coracle {
        dir = "both"
        
        # Filter to only sync event kind 10002
        filter = {
            "kinds": [10002]
        }
        
        urls = [
            "wss://indexer.coracle.social/"
        ]
        
        # Optional: Add plugin for additional filtering if needed
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
        # pluginUp = "/etc/strfry/plugins/validate-events.js"
    }
    
    # One-way sync (down only) from Damus relay
    # Only download event kinds 3 and 10002, don't push local events
    damus {
        dir = "down"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://relay.damus.io/"
        ]
        
        # Optional: Add plugin for validation/filtering
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
    }
    
    # One-way sync (down only) from Primal relay
    # Only download event kinds 3 and 10002, don't push local events
    primal {
        dir = "down"
        
        # Filter to only sync event kinds 3 and 10002
        filter = {
            "kinds": [3, 10002]
        }
        
        urls = [
            "wss://relay.primal.net/"
        ]
        
        # Optional: Add plugin for validation/filtering
        # pluginDown = "/etc/strfry/plugins/validate-events.js"
    }
}

# Optional: Performance tuning
# maxConcurrentConnections = 10
# reconnectDelaySeconds = 5
# maxEventsPerSecond = 100
EOF

echo "Configuration file created. Current region: $CURRENT_REGION"
echo "Nostria Discovery Relay sync entries added:"
if [ "$CURRENT_REGION" != "eu" ]; then
    echo "  ✓ nostria_eu (EU Discovery Relay)"
fi
if [ "$CURRENT_REGION" != "us" ]; then
    echo "  ✓ nostria_us (US Discovery Relay)"
fi
if [ "$CURRENT_REGION" != "af" ]; then
    echo "  ✓ nostria_af (AF Discovery Relay)"
fi

# Set proper ownership
chown root:root /etc/strfry/strfry-router.conf
chmod 644 /etc/strfry/strfry-router.conf

# Verify the configuration was written correctly
echo ""
echo "=== Configuration File Verification ==="
echo "Contents of /etc/strfry/strfry-router.conf:"
echo "----------------------------------------"
cat /etc/strfry/strfry-router.conf
echo "----------------------------------------"
echo ""

# Count the number of stream entries
STREAM_COUNT=$(grep -c "^\s*[a-zA-Z_]*\s*{" /etc/strfry/strfry-router.conf || echo "0")
echo "Number of sync streams configured: $STREAM_COUNT"
echo ""

# Create the systemd service file
echo "Creating strfry router systemd service..."
cat > /etc/systemd/system/strfry-router.service << 'EOF'
[Unit]
Description=strfry nostr router for discovery relay sync
After=network.target strfry.service
Wants=network.target
Requires=strfry.service

[Service]
Type=simple
User=strfry
Group=strfry
ExecStart=/usr/local/bin/strfry --config=/etc/strfry/strfry.conf router /etc/strfry/strfry-router.conf
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=strfry-router

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/strfry /var/log/strfry
ReadOnlyPaths=/etc/strfry

# Environment variables
Environment=STRFRY_DB=/var/lib/strfry/db

# File descriptor limits
LimitNOFILE=524288

# Restart policy - be more patient with network issues
RestartPreventExitStatus=0
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Test the router configuration
echo "Testing strfry router configuration..."
if sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf router /etc/strfry/strfry-router.conf --help >/dev/null 2>&1; then
    echo "SUCCESS: Router configuration appears valid"
else
    echo "WARNING: Could not validate router configuration, but proceeding with setup"
    echo "This is normal if strfry doesn't support config validation"
fi

# Enable and start the router service
echo "Enabling and starting strfry router service..."
systemctl daemon-reload
systemctl enable strfry-router

# Make sure main strfry service is running first
if ! systemctl is-active --quiet strfry; then
    echo "Starting main strfry service first..."
    systemctl start strfry
    sleep 5
fi

# Start the router service
echo "Starting strfry router service..."
systemctl start strfry-router

# Wait a moment for startup
sleep 10

# Check service status
echo "Checking service status..."
if systemctl is-active --quiet strfry-router; then
    echo "SUCCESS: strfry router service is running"
    
    # Show recent logs
    echo "Recent logs from strfry router:"
    journalctl -u strfry-router --no-pager -n 20 || true
else
    echo "ERROR: strfry router service failed to start"
    echo "Service status:"
    systemctl status strfry-router --no-pager -l || true
    echo "Recent logs:"
    journalctl -u strfry-router --no-pager -n 20 || true
    exit 1
fi

# Create monitoring script for router sync
echo "Creating router monitoring script..."
cat > /usr/local/bin/strfry-router-monitor.sh << 'EOF'
#!/bin/bash
# Monitor strfry router sync status

echo "=== Strfry Router Sync Monitor ==="
echo "Timestamp: $(date)"

# Detect current region
HOSTNAME=$(hostname)
CURRENT_REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -n "$CURRENT_REGION" ]; then
    echo "Current region: $CURRENT_REGION"
else
    echo "Region: Unknown (hostname: $HOSTNAME)"
fi

# Check if router service is running
if systemctl is-active --quiet strfry-router; then
    echo "✓ Router service is running"
else
    echo "✗ Router service is not running"
    systemctl status strfry-router --no-pager -l || true
    exit 1
fi

# Check database for event kinds 3 and 10002
echo -e "\n=== Event Counts in Database ==="
echo "Contact lists (kind 3):"
strfry scan '{"kinds":[3]}' 2>/dev/null | wc -l || echo "Error scanning kind 3 events"

echo "Relay lists (kind 10002):"
strfry scan '{"kinds":[10002]}' 2>/dev/null | wc -l || echo "Error scanning kind 10002 events"

# Test connectivity to other Discovery Relays
echo -e "\n=== Discovery Relay Connectivity ==="
if [ "$CURRENT_REGION" != "eu" ]; then
    if curl -s --connect-timeout 5 https://discovery.eu.nostria.app/health >/dev/null 2>&1; then
        echo "✓ discovery.eu.nostria.app is reachable"
    else
        echo "✗ discovery.eu.nostria.app is not reachable"
    fi
fi

if [ "$CURRENT_REGION" != "us" ]; then
    if curl -s --connect-timeout 5 https://discovery.us.nostria.app/health >/dev/null 2>&1; then
        echo "✓ discovery.us.nostria.app is reachable"
    else
        echo "✗ discovery.us.nostria.app is not reachable"
    fi
fi

if [ "$CURRENT_REGION" != "af" ]; then
    if curl -s --connect-timeout 5 https://discovery.af.nostria.app/health >/dev/null 2>&1; then
        echo "✓ discovery.af.nostria.app is reachable"
    else
        echo "✗ discovery.af.nostria.app is not reachable"
    fi
fi

# Test external relay connectivity
echo -e "\n=== External Relay Connectivity ==="
if curl -s --connect-timeout 5 https://purplepag.es/health >/dev/null 2>&1 || curl -s --connect-timeout 5 https://purplepag.es/ >/dev/null 2>&1; then
    echo "✓ purplepag.es is reachable"
else
    echo "✗ purplepag.es is not reachable"
fi

if curl -s --connect-timeout 5 https://indexer.coracle.social/ >/dev/null 2>&1; then
    echo "✓ indexer.coracle.social is reachable"
else
    echo "✗ indexer.coracle.social is not reachable"
fi

# Show recent router logs
echo -e "\n=== Recent Router Logs ==="
journalctl -u strfry-router --no-pager -n 15 --since "10 minutes ago" || true

# Show network connections
echo -e "\n=== Active Network Connections ==="
ss -tuln | grep -E "(7777|443)" || echo "No relay connections visible"

echo -e "\n=== Router Monitor Complete ==="
EOF

chmod +x /usr/local/bin/strfry-router-monitor.sh

# Add cron job for monitoring
echo "Setting up router monitoring..."
cat > /etc/cron.d/strfry-router-monitor << 'EOF'
# Monitor strfry router sync every 30 minutes
*/30 * * * * root /usr/local/bin/strfry-router-monitor.sh >> /var/log/strfry-router-monitor.log 2>&1
EOF

echo -e "\n=== Strfry Router Setup Complete ==="
echo "Configuration for region: $CURRENT_REGION"
echo "Two-way sync configured with:"
if [ "$CURRENT_REGION" != "eu" ]; then
    echo "  - discovery.eu.nostria.app (Nostria EU Discovery Relay)"
fi
if [ "$CURRENT_REGION" != "us" ]; then
    echo "  - discovery.us.nostria.app (Nostria US Discovery Relay)"
fi
if [ "$CURRENT_REGION" != "af" ]; then
    echo "  - discovery.af.nostria.app (Nostria AF Discovery Relay)"
fi
echo "  - purplepag.es (External relay)"
echo "  - indexer.coracle.social (Coracle indexer)"
echo ""
echo "One-way sync (download only) from:"
echo "  - relay.damus.io"
echo "  - relay.primal.net"
echo "  - Event kinds: 3 (contact lists), 10002 (relay lists)"
echo ""
echo "Services:"
echo "  - strfry.service: Main relay"
echo "  - strfry-router.service: Sync router"
echo ""
echo "⚠️  IMPORTANT: Initial Full Sync Recommended"
echo "The router service only syncs NEW events going forward."
echo "To sync existing historical events, run the initial full sync:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash"
echo ""
echo "Monitoring:"
echo "  - Run: /usr/local/bin/strfry-router-monitor.sh"
echo "  - Logs: journalctl -u strfry-router -f"
echo "  - Status: systemctl status strfry-router"
echo ""
echo "Configuration files:"
echo "  - Router config: /etc/strfry/strfry-router.conf"
echo "  - Service file: /etc/systemd/system/strfry-router.service"

# Run initial monitor
echo -e "\n=== Initial Router Status ==="
/usr/local/bin/strfry-router-monitor.sh
