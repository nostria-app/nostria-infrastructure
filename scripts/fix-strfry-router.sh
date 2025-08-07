#!/bin/bash
# Quick fix for strfry router service configuration
# This fixes the ExecStart command to include the main strfry config

echo "=== Fixing Strfry Router Service Configuration ==="
echo "Timestamp: $(date)"

# Stop the failing service
echo "Stopping strfry-router service..."
systemctl stop strfry-router || true

# Update the service file with the correct ExecStart command
echo "Updating service configuration..."
sed -i 's|ExecStart=/usr/local/bin/strfry router|ExecStart=/usr/local/bin/strfry --config=/etc/strfry/strfry.conf router|g' /etc/systemd/system/strfry-router.service

# Reload systemd and restart the service
echo "Reloading systemd configuration..."
systemctl daemon-reload

echo "Starting strfry-router service..."
systemctl start strfry-router

# Wait for startup
sleep 5

# Check status
echo "Checking service status..."
if systemctl is-active --quiet strfry-router; then
    echo "SUCCESS: strfry-router service is now running"
    
    # Show recent logs
    echo "Recent logs:"
    journalctl -u strfry-router --no-pager -n 10 || true
else
    echo "ERROR: strfry-router service still failing"
    echo "Service status:"
    systemctl status strfry-router --no-pager -l || true
    echo "Recent logs:"
    journalctl -u strfry-router --no-pager -n 20 || true
fi

echo "=== Fix Complete ==="
