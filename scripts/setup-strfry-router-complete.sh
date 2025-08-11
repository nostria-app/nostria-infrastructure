#!/bin/bash
# Complete setup script for strfry router with initial full sync
# This script sets up the router configuration and performs initial historical sync

set -e

echo "=== Complete Strfry Router Setup with Initial Sync ==="
echo "Timestamp: $(date)"

# Step 1: Setup router configuration and service
echo ""
echo "Step 1/2: Setting up strfry router configuration..."
if curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash; then
    echo "✓ Router setup completed successfully"
else
    echo "✗ Router setup failed"
    exit 1
fi

# Step 2: Run initial full sync
echo ""
echo "Step 2/2: Running initial full sync of historical events..."
echo "This may take several minutes..."

if curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash; then
    echo "✓ Initial full sync completed successfully"
else
    echo "✗ Initial full sync failed or partially completed"
    echo "You can retry the sync later with:"
    echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash"
fi

echo ""
echo "=== Complete Router Setup Finished ==="
echo ""
echo "Your discovery relay is now configured with:"
echo "✓ Router service for continuous sync of new events"
echo "✓ Initial historical sync of existing events"
echo ""
echo "Monitor sync activity:"
echo "  sudo journalctl -u strfry-router -f"
echo "  sudo /usr/local/bin/strfry-router-monitor.sh"
echo ""
echo "Check service status:"
echo "  sudo systemctl status strfry"
echo "  sudo systemctl status strfry-router"
