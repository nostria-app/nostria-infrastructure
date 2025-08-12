#!/bin/bash
# Quick migration script: index.eu.nostria.app → discovery.eu.nostria.app
# This script updates Caddy configuration and renews certificates

set -e

echo "=== Quick Domain Migration: index.eu.nostria.app → discovery.eu.nostria.app ==="
echo "Timestamp: $(date)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Run as root: sudo $0"
    exit 1
fi

# Configuration
OLD_DOMAIN="index.eu.nostria.app"
NEW_DOMAIN="discovery.eu.nostria.app"
CADDYFILE="/etc/caddy/Caddyfile"

echo ""
echo "Step 1: Backing up current Caddyfile..."
cp "$CADDYFILE" "$CADDYFILE.backup-$(date +%Y%m%d-%H%M%S)"
echo "✓ Backup created"

echo ""
echo "Step 2: Updating domain in Caddyfile..."
if grep -q "$OLD_DOMAIN" "$CADDYFILE"; then
    sed -i "s/$OLD_DOMAIN/$NEW_DOMAIN/g" "$CADDYFILE"
    echo "✓ Domain updated: $OLD_DOMAIN → $NEW_DOMAIN"
else
    echo "⚠️  $OLD_DOMAIN not found in Caddyfile"
    echo "Current Caddyfile content:"
    cat "$CADDYFILE"
    exit 1
fi

echo ""
echo "Step 3: Validating new configuration..."
if caddy validate --config "$CADDYFILE"; then
    echo "✓ Configuration is valid"
else
    echo "✗ Configuration is invalid - restoring backup"
    cp "$CADDYFILE.backup-$(date +%Y%m%d-%H%M%S)" "$CADDYFILE"
    exit 1
fi

echo ""
echo "Step 4: Cleaning old certificates..."
rm -rf /var/lib/caddy/certificates/acme-v02.api.letsencrypt.org-directory/*"$OLD_DOMAIN"* 2>/dev/null || true
rm -rf /var/lib/caddy/certificates/acme-staging-v02.api.letsencrypt.org-directory/*"$OLD_DOMAIN"* 2>/dev/null || true
echo "✓ Old certificates cleaned"

echo ""
echo "Step 5: Restarting Caddy..."
systemctl restart caddy

echo "Waiting for service to start..."
sleep 5

if systemctl is-active --quiet caddy; then
    echo "✓ Caddy is running"
else
    echo "✗ Caddy failed to start"
    systemctl status caddy --no-pager -l
    exit 1
fi

echo ""
echo "Step 6: Testing new domain..."
echo "Testing HTTP..."
if curl -s --connect-timeout 10 "http://$NEW_DOMAIN/health" >/dev/null 2>&1; then
    echo "✓ HTTP works"
else
    echo "⚠️  HTTP failed (may redirect to HTTPS)"
fi

echo "Testing HTTPS (may take 1-2 minutes for certificate)..."
for i in {1..6}; do
    if curl -s --connect-timeout 15 "https://$NEW_DOMAIN/health" >/dev/null 2>&1; then
        echo "✓ HTTPS works! Certificate acquired successfully"
        break
    else
        echo "  Attempt $i/6 failed, waiting 15 seconds..."
        sleep 15
    fi
done

echo ""
echo "=== Migration Complete ==="
echo "New domain: https://$NEW_DOMAIN"
echo "Monitor certificate acquisition: sudo journalctl -u caddy -f"
echo ""
echo "If issues occur, restore backup:"
echo "  sudo cp $CADDYFILE.backup-* $CADDYFILE"
echo "  sudo systemctl restart caddy"
