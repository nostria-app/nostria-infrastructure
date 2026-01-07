#!/bin/bash
# Quick one-time sync with purplepages relay - optimized for large datasets
# This script performs a fast sync WITHOUT pre/post event counting

set -e

echo "=== Quick Sync with purplepages.es ==="
echo "Started: $(date)"
echo ""

# Configuration
RELAY_URL="wss://purplepag.es/"
RELAY_NAME="purplepages"
TIMEOUT=600  # 10 minutes timeout
FILTER='{"kinds":[3,10002]}'

# Verify prerequisites
if ! command -v strfry &> /dev/null; then
    echo "ERROR: strfry binary not found"
    exit 1
fi

if ! id strfry &>/dev/null; then
    echo "ERROR: strfry user does not exist"
    exit 1
fi

if ! systemctl is-active --quiet strfry; then
    echo "ERROR: Main strfry service is not running"
    echo "Start it with: sudo systemctl start strfry"
    exit 1
fi

# Quick connectivity check
echo "Checking connectivity to $RELAY_NAME..."
DOMAIN=$(echo "$RELAY_URL" | sed 's|wss://||' | sed 's|/.*||')

if ! curl -s --connect-timeout 5 "https://$DOMAIN" >/dev/null 2>&1; then
    echo "WARNING: Could not reach $DOMAIN - sync may fail"
    echo "Continue anyway? (y/n)"
    read -r CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        echo "Aborted"
        exit 1
    fi
fi

echo "✓ $RELAY_NAME is reachable"
echo ""

# Stop router if running to avoid conflicts
ROUTER_WAS_RUNNING=false
if systemctl is-active --quiet strfry-router; then
    echo "Temporarily stopping strfry-router to avoid conflicts..."
    systemctl stop strfry-router
    ROUTER_WAS_RUNNING=true
    sleep 2
fi

# Perform the sync
echo "=== Starting Sync ==="
echo "Target: $RELAY_URL"
echo "Filter: $FILTER"
echo "Timeout: ${TIMEOUT}s"
echo "Direction: bidirectional (both upload and download)"
echo ""
echo "This will sync all contact lists (kind 3) and relay lists (kind 10002)."
echo "Large datasets may take several minutes..."
echo ""

# Build and execute sync command
SYNC_CMD="sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf sync \"$RELAY_URL\" --filter '$FILTER'"

echo "Running: $SYNC_CMD"
echo ""

START_TIME=$(date +%s)

# Execute with timeout and stream output
if timeout $TIMEOUT bash -c "$SYNC_CMD"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "✓ Sync completed successfully"
    echo "Duration: ${DURATION}s"
    
    SYNC_SUCCESS=true
else
    EXIT_CODE=$?
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    if [ $EXIT_CODE -eq 124 ]; then
        echo "✗ Sync timed out after ${TIMEOUT}s"
    else
        echo "✗ Sync failed with exit code $EXIT_CODE"
    fi
    echo "Duration: ${DURATION}s"
    
    SYNC_SUCCESS=false
fi

# Restart router if it was running
if [ "$ROUTER_WAS_RUNNING" = true ]; then
    echo ""
    echo "Restarting strfry-router service..."
    systemctl start strfry-router
    sleep 3
    
    if systemctl is-active --quiet strfry-router; then
        echo "✓ Router service restarted"
    else
        echo "✗ Failed to restart router - check logs:"
        echo "  sudo journalctl -u strfry-router -n 50"
    fi
fi

# Summary
echo ""
echo "=== Sync Complete ==="
echo "Completed: $(date)"
echo ""

if [ "$SYNC_SUCCESS" = true ]; then
    echo "✓ Successfully synchronized with $RELAY_NAME"
    echo ""
    echo "What was synced:"
    echo "  • Contact lists (kind 3) - bidirectional"
    echo "  • Relay lists (kind 10002) - bidirectional"
    echo ""
    echo "The continuous sync service (strfry-router) will now maintain ongoing synchronization."
else
    echo "✗ Sync failed"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check network: curl -I https://$DOMAIN"
    echo "  2. Check strfry logs: sudo journalctl -u strfry -n 100"
    echo "  3. Verify relay is accessible: wscat -c $RELAY_URL"
    echo "  4. Try manual sync with smaller filter:"
    echo "     sudo -u strfry strfry sync $RELAY_URL --filter '{\"kinds\":[10002]}' --dir=down"
fi

echo ""
echo "To check if events are present:"
echo "  # Count kind 3 events: sudo -u strfry strfry scan '{\"kinds\":[3]}' | wc -l"
echo "  # Count kind 10002 events: sudo -u strfry strfry scan '{\"kinds\":[10002]}' | wc -l"

exit $([ "$SYNC_SUCCESS" = true ] && echo 0 || echo 1)
