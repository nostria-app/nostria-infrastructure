#!/bin/bash
# Initial full synchronization script for strfry router
# This script performs a one-time full sync of existing events from all configured relays
# before starting the continuous router sync service

set -e

echo "=== Strfry Initial Full Sync ==="
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

# Check if main strfry service is running
if ! systemctl is-active --quiet strfry; then
    echo "ERROR: Main strfry service is not running. Please start it first:"
    echo "  sudo systemctl start strfry"
    exit 1
fi

# Determine current region from hostname to avoid self-sync
HOSTNAME=$(hostname)
CURRENT_REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')
if [ -z "$CURRENT_REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the current region (eu, us, af):"
    read -r CURRENT_REGION
fi

echo "Detected current region: $CURRENT_REGION"

# Function to check relay connectivity
check_relay_connectivity() {
    local relay_url="$1"
    local relay_name="$2"
    
    echo "Checking connectivity to $relay_name ($relay_url)..."
    
    # Extract domain from WebSocket URL
    local domain=$(echo "$relay_url" | sed 's|wss://||' | sed 's|/.*||')
    
    if curl -s --connect-timeout 10 "https://$domain" >/dev/null 2>&1 || \
       curl -s --connect-timeout 10 "https://$domain/health" >/dev/null 2>&1; then
        echo "✓ $relay_name is reachable"
        return 0
    else
        echo "✗ $relay_name is not reachable - skipping"
        return 1
    fi
}

# Function to perform sync with retry logic
sync_with_retry() {
    local relay_url="$1"
    local relay_name="$2"
    local direction="$3"
    local max_retries="$4"
    local retry_delay="$5"
    
    echo ""
    echo "=== Syncing with $relay_name ==="
    echo "URL: $relay_url"
    echo "Direction: $direction"
    echo "Filter: kinds 3 (contact lists) and 10002 (relay lists)"
    
    local retry_count=0
    while [ $retry_count -lt $max_retries ]; do
        echo "Attempt $((retry_count + 1))/$max_retries..."
        
        # Build the sync command
        local sync_cmd="sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf sync \"$relay_url\" --filter '{\"kinds\":[3,10002]}'"
        
        # Add direction if specified
        if [ "$direction" = "down" ]; then
            sync_cmd="$sync_cmd --dir down"
        fi
        
        echo "Running: $sync_cmd"
        
        # Execute the sync command with timeout
        if timeout 300 bash -c "$sync_cmd"; then
            echo "✓ Successfully synced with $relay_name"
            return 0
        else
            local exit_code=$?
            echo "✗ Sync failed with exit code $exit_code"
            
            if [ $retry_count -lt $((max_retries - 1)) ]; then
                echo "Waiting $retry_delay seconds before retry..."
                sleep $retry_delay
            fi
        fi
        
        retry_count=$((retry_count + 1))
    done
    
    echo "✗ Failed to sync with $relay_name after $max_retries attempts"
    return 1
}

# Function to count events before and after sync
count_events() {
    local kind="$1"
    local description="$2"
    
    local count=$(sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan "{\"kinds\":[$kind]}" 2>/dev/null | wc -l || echo "0")
    echo "$description (kind $kind): $count events"
}

# Show initial event counts
echo ""
echo "=== Initial Event Counts ==="
count_events "3" "Contact lists"
count_events "10002" "Relay lists"

# Stop router service if running to avoid conflicts
if systemctl is-active --quiet strfry-router; then
    echo ""
    echo "Stopping strfry-router service to avoid conflicts during initial sync..."
    systemctl stop strfry-router
    ROUTER_WAS_RUNNING=true
else
    ROUTER_WAS_RUNNING=false
fi

# Configuration for sync attempts
MAX_RETRIES=3
RETRY_DELAY=30

echo ""
echo "=== Starting Initial Full Sync ==="
echo "This may take several minutes depending on the amount of historical data..."

# Track sync results
SUCCESSFUL_SYNCS=0
FAILED_SYNCS=0

# Sync with other Nostria Discovery Relays (excluding current region)
if [ "$CURRENT_REGION" != "eu" ]; then
    if check_relay_connectivity "wss://discovery.eu.nostria.app/" "Nostria EU Discovery Relay"; then
        if sync_with_retry "wss://discovery.eu.nostria.app/" "Nostria EU Discovery Relay" "both" $MAX_RETRIES $RETRY_DELAY; then
            SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
        else
            FAILED_SYNCS=$((FAILED_SYNCS + 1))
        fi
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
fi

if [ "$CURRENT_REGION" != "us" ]; then
    if check_relay_connectivity "wss://discovery.us.nostria.app/" "Nostria US Discovery Relay"; then
        if sync_with_retry "wss://discovery.us.nostria.app/" "Nostria US Discovery Relay" "both" $MAX_RETRIES $RETRY_DELAY; then
            SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
        else
            FAILED_SYNCS=$((FAILED_SYNCS + 1))
        fi
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
fi

if [ "$CURRENT_REGION" != "af" ]; then
    if check_relay_connectivity "wss://discovery.af.nostria.app/" "Nostria AF Discovery Relay"; then
        if sync_with_retry "wss://discovery.af.nostria.app/" "Nostria AF Discovery Relay" "both" $MAX_RETRIES $RETRY_DELAY; then
            SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
        else
            FAILED_SYNCS=$((FAILED_SYNCS + 1))
        fi
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
fi

# Sync with external relays
echo ""
echo "=== Syncing with External Relays ==="

# purplepag.es (two-way sync)
if check_relay_connectivity "wss://purplepag.es/" "purplepag.es"; then
    if sync_with_retry "wss://purplepag.es/" "purplepag.es" "both" $MAX_RETRIES $RETRY_DELAY; then
        SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
else
    FAILED_SYNCS=$((FAILED_SYNCS + 1))
fi

# index.eu.nostria.app (two-way sync)
if check_relay_connectivity "wss://index.eu.nostria.app/" "Nostria EU Index Relay"; then
    if sync_with_retry "wss://index.eu.nostria.app/" "Nostria EU Index Relay" "both" $MAX_RETRIES $RETRY_DELAY; then
        SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
else
    FAILED_SYNCS=$((FAILED_SYNCS + 1))
fi

# relay.damus.io (one-way sync down)
if check_relay_connectivity "wss://relay.damus.io/" "relay.damus.io"; then
    if sync_with_retry "wss://relay.damus.io/" "relay.damus.io" "down" $MAX_RETRIES $RETRY_DELAY; then
        SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
else
    FAILED_SYNCS=$((FAILED_SYNCS + 1))
fi

# relay.primal.net (one-way sync down)
if check_relay_connectivity "wss://relay.primal.net/" "relay.primal.net"; then
    if sync_with_retry "wss://relay.primal.net/" "relay.primal.net" "down" $MAX_RETRIES $RETRY_DELAY; then
        SUCCESSFUL_SYNCS=$((SUCCESSFUL_SYNCS + 1))
    else
        FAILED_SYNCS=$((FAILED_SYNCS + 1))
    fi
else
    FAILED_SYNCS=$((FAILED_SYNCS + 1))
fi

# Show final event counts
echo ""
echo "=== Final Event Counts ==="
count_events "3" "Contact lists"
count_events "10002" "Relay lists"

# Show sync summary
echo ""
echo "=== Sync Summary ==="
echo "Successful syncs: $SUCCESSFUL_SYNCS"
echo "Failed syncs: $FAILED_SYNCS"
echo "Total relays attempted: $((SUCCESSFUL_SYNCS + FAILED_SYNCS))"

# Restart router service if it was running
if [ "$ROUTER_WAS_RUNNING" = true ]; then
    echo ""
    echo "Restarting strfry-router service..."
    systemctl start strfry-router
    
    # Wait for service to start
    sleep 5
    
    if systemctl is-active --quiet strfry-router; then
        echo "✓ strfry-router service restarted successfully"
    else
        echo "✗ Failed to restart strfry-router service"
        echo "Please check logs: journalctl -u strfry-router -n 20"
    fi
fi

# Final recommendations
echo ""
echo "=== Initial Full Sync Complete ==="
echo ""
if [ $SUCCESSFUL_SYNCS -gt 0 ]; then
    echo "✓ Successfully synchronized with $SUCCESSFUL_SYNCS relay(s)"
    echo ""
    echo "The strfry router service will now maintain continuous sync of new events."
    echo "You can monitor ongoing sync activity with:"
    echo "  sudo journalctl -u strfry-router -f"
    echo "  sudo /usr/local/bin/strfry-router-monitor.sh"
else
    echo "✗ No successful syncs completed"
    echo ""
    echo "Please check:"
    echo "1. Network connectivity to relay endpoints"
    echo "2. DNS resolution for relay domains"
    echo "3. Firewall settings allowing outbound connections"
    echo "4. strfry service is running: systemctl status strfry"
fi

if [ $FAILED_SYNCS -gt 0 ]; then
    echo ""
    echo "⚠️  Warning: $FAILED_SYNCS relay(s) failed to sync"
    echo "These relays may be temporarily unavailable or have connectivity issues."
    echo "The router service will continue attempting to sync with them automatically."
fi

echo ""
echo "To run this initial sync again:"
echo "  sudo curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash"
echo ""
echo "To check current sync status:"
echo "  sudo /usr/local/bin/strfry-router-monitor.sh"
