#!/bin/bash
# Script to migrate Caddy domain from index.eu.nostria.app to discovery.eu.nostria.app
# This script updates the Caddyfile configuration and handles certificate renewal

set -e

echo "=== Caddy Domain Migration Script ==="
echo "Timestamp: $(date)"
echo "Migrating from: index.eu.nostria.app"
echo "Migrating to: discovery.eu.nostria.app"

# Configuration
OLD_DOMAIN="index.eu.nostria.app"
NEW_DOMAIN="discovery.eu.nostria.app"
CADDYFILE_PATH="/etc/caddy/Caddyfile"
CADDY_DATA_DIR="/var/lib/caddy"
BACKUP_DIR="/tmp/caddy-migration-backup-$(date +%Y%m%d-%H%M%S)"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)"
    exit 1
fi

# Check if Caddy is installed
if ! command -v caddy &> /dev/null; then
    echo "ERROR: Caddy is not installed or not in PATH"
    exit 1
fi

# Check if Caddyfile exists
if [ ! -f "$CADDYFILE_PATH" ]; then
    echo "ERROR: Caddyfile not found at $CADDYFILE_PATH"
    exit 1
fi

# Function to check domain resolution
check_domain_resolution() {
    local domain="$1"
    echo "Checking DNS resolution for $domain..."
    
    if nslookup "$domain" >/dev/null 2>&1; then
        echo "✓ $domain resolves correctly"
        return 0
    else
        echo "✗ $domain does not resolve"
        return 1
    fi
}

# Function to check domain connectivity
check_domain_connectivity() {
    local domain="$1"
    echo "Checking HTTP connectivity to $domain..."
    
    if curl -s --connect-timeout 10 "https://$domain" >/dev/null 2>&1 || \
       curl -s --connect-timeout 10 "http://$domain" >/dev/null 2>&1; then
        echo "✓ $domain is reachable"
        return 0
    else
        echo "✗ $domain is not reachable"
        return 1
    fi
}

# Create backup directory
echo ""
echo "=== Creating Backup ==="
mkdir -p "$BACKUP_DIR"

# Backup current Caddyfile
echo "Backing up current Caddyfile..."
cp "$CADDYFILE_PATH" "$BACKUP_DIR/Caddyfile.backup"
echo "✓ Caddyfile backed up to: $BACKUP_DIR/Caddyfile.backup"

# Backup Caddy data directory (certificates, etc.)
echo "Backing up Caddy data directory..."
if [ -d "$CADDY_DATA_DIR" ]; then
    cp -r "$CADDY_DATA_DIR" "$BACKUP_DIR/caddy-data-backup"
    echo "✓ Caddy data backed up to: $BACKUP_DIR/caddy-data-backup"
else
    echo "⚠️  Caddy data directory not found at $CADDY_DATA_DIR"
fi

# Show current Caddyfile content
echo ""
echo "=== Current Caddyfile Content ==="
echo "File: $CADDYFILE_PATH"
echo "----------------------------------------"
cat "$CADDYFILE_PATH"
echo "----------------------------------------"

# Check if old domain exists in Caddyfile
if ! grep -q "$OLD_DOMAIN" "$CADDYFILE_PATH"; then
    echo ""
    echo "⚠️  WARNING: $OLD_DOMAIN not found in Caddyfile"
    echo "Current domains in Caddyfile:"
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" "$CADDYFILE_PATH" || echo "No domains found"
    echo ""
    echo "Do you want to continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Migration cancelled"
        exit 1
    fi
fi

# Check new domain DNS resolution
echo ""
echo "=== Pre-Migration Checks ==="
if ! check_domain_resolution "$NEW_DOMAIN"; then
    echo ""
    echo "⚠️  WARNING: $NEW_DOMAIN does not resolve to this server"
    echo "Please ensure DNS is configured to point $NEW_DOMAIN to this server's IP address"
    echo ""
    echo "Current server IP addresses:"
    ip addr show | grep -E "inet [0-9]" | grep -v "127.0.0.1" | awk '{print "  " $2}' || true
    echo ""
    echo "Do you want to continue anyway? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Migration cancelled. Please configure DNS first."
        exit 1
    fi
fi

# Update Caddyfile
echo ""
echo "=== Updating Caddyfile ==="
echo "Replacing $OLD_DOMAIN with $NEW_DOMAIN..."

# Create temporary file with updated content
sed "s/$OLD_DOMAIN/$NEW_DOMAIN/g" "$CADDYFILE_PATH" > "$CADDYFILE_PATH.tmp"

# Show the changes
echo ""
echo "=== Changes Preview ==="
echo "Old configuration:"
grep -n "$OLD_DOMAIN" "$CADDYFILE_PATH" || echo "  (no matches found)"
echo ""
echo "New configuration:"
grep -n "$NEW_DOMAIN" "$CADDYFILE_PATH.tmp" || echo "  (no matches found)"

# Validate new Caddyfile syntax
echo ""
echo "=== Validating New Configuration ==="
if caddy validate --config "$CADDYFILE_PATH.tmp"; then
    echo "✓ New Caddyfile syntax is valid"
else
    echo "✗ New Caddyfile syntax is invalid"
    echo "Restoring original configuration..."
    rm "$CADDYFILE_PATH.tmp"
    exit 1
fi

# Apply the changes
echo ""
echo "=== Applying Configuration Changes ==="
mv "$CADDYFILE_PATH.tmp" "$CADDYFILE_PATH"
echo "✓ Caddyfile updated successfully"

# Show updated Caddyfile
echo ""
echo "=== Updated Caddyfile Content ==="
echo "----------------------------------------"
cat "$CADDYFILE_PATH"
echo "----------------------------------------"

# Remove old domain certificates to force renewal
echo ""
echo "=== Cleaning Old Certificates ==="
if [ -d "$CADDY_DATA_DIR" ]; then
    # Find and remove old domain certificates
    find "$CADDY_DATA_DIR" -name "*$OLD_DOMAIN*" -type f -delete 2>/dev/null || true
    find "$CADDY_DATA_DIR" -name "*$OLD_DOMAIN*" -type d -exec rm -rf {} + 2>/dev/null || true
    echo "✓ Old domain certificates cleaned"
else
    echo "⚠️  Caddy data directory not found, skipping certificate cleanup"
fi

# Reload Caddy configuration
echo ""
echo "=== Reloading Caddy Configuration ==="

# Stop Caddy service first
echo "Stopping Caddy service..."
systemctl stop caddy || true
sleep 2

# Start Caddy service
echo "Starting Caddy service with new configuration..."
if systemctl start caddy; then
    echo "✓ Caddy service started successfully"
else
    echo "✗ Failed to start Caddy service"
    echo ""
    echo "Attempting to restore backup..."
    cp "$BACKUP_DIR/Caddyfile.backup" "$CADDYFILE_PATH"
    systemctl start caddy
    echo "✗ Migration failed - configuration restored"
    exit 1
fi

# Wait for service to stabilize
echo "Waiting for Caddy to stabilize..."
sleep 10

# Check service status
if systemctl is-active --quiet caddy; then
    echo "✓ Caddy service is running"
else
    echo "✗ Caddy service is not running"
    echo "Service status:"
    systemctl status caddy --no-pager -l
    exit 1
fi

# Test new domain connectivity
echo ""
echo "=== Testing New Domain ==="

# Test HTTP first
echo "Testing HTTP connectivity..."
if curl -s --connect-timeout 10 "http://$NEW_DOMAIN/health" >/dev/null 2>&1 || \
   curl -s --connect-timeout 10 "http://$NEW_DOMAIN/" >/dev/null 2>&1; then
    echo "✓ HTTP connectivity successful"
else
    echo "⚠️  HTTP connectivity failed (this may be normal if HTTPS redirect is enabled)"
fi

# Test HTTPS with retry logic
echo "Testing HTTPS connectivity..."
HTTPS_SUCCESS=false
for attempt in {1..5}; do
    echo "  Attempt $attempt/5..."
    if curl -s --connect-timeout 15 "https://$NEW_DOMAIN/health" >/dev/null 2>&1 || \
       curl -s --connect-timeout 15 "https://$NEW_DOMAIN/" >/dev/null 2>&1; then
        echo "✓ HTTPS connectivity successful"
        HTTPS_SUCCESS=true
        break
    else
        if [ $attempt -lt 5 ]; then
            echo "  Retrying in 10 seconds..."
            sleep 10
        fi
    fi
done

if [ "$HTTPS_SUCCESS" = false ]; then
    echo "⚠️  HTTPS connectivity failed - certificate may still be acquiring"
    echo "This is normal for new domains. Certificate acquisition can take a few minutes."
fi

# Show certificate status
echo ""
echo "=== Certificate Status ==="
echo "Checking Let's Encrypt certificate acquisition..."

# Check Caddy logs for certificate status
echo "Recent Caddy logs (certificate acquisition):"
journalctl -u caddy --no-pager -n 20 --since "5 minutes ago" | grep -i -E "(certificate|acme|tls|error)" || echo "No certificate-related logs found"

# Test certificate with openssl
echo ""
echo "Testing certificate with OpenSSL..."
if timeout 15 openssl s_client -connect "$NEW_DOMAIN:443" -servername "$NEW_DOMAIN" </dev/null 2>/dev/null | grep -q "CONNECTED"; then
    echo "✓ TLS connection successful"
    # Get certificate details
    echo "Certificate details:"
    timeout 15 openssl s_client -connect "$NEW_DOMAIN:443" -servername "$NEW_DOMAIN" </dev/null 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "Could not retrieve certificate details"
else
    echo "⚠️  TLS connection failed or certificate not ready yet"
fi

# Final status summary
echo ""
echo "=== Migration Summary ==="
echo "✓ Configuration backed up to: $BACKUP_DIR"
echo "✓ Caddyfile updated: $OLD_DOMAIN → $NEW_DOMAIN"
echo "✓ Old certificates cleaned"
echo "✓ Caddy service reloaded"

if [ "$HTTPS_SUCCESS" = true ]; then
    echo "✓ HTTPS connectivity confirmed"
else
    echo "⚠️  HTTPS connectivity pending (certificate acquisition in progress)"
fi

echo ""
echo "=== Next Steps ==="
echo "1. Monitor certificate acquisition: sudo journalctl -u caddy -f"
echo "2. Test endpoints:"
echo "   curl -v http://$NEW_DOMAIN/health"
echo "   curl -v https://$NEW_DOMAIN/health"
echo "3. Update any applications or configurations that reference the old domain"
echo "4. Update DNS records if needed"
echo ""
echo "If there are issues, you can restore from backup:"
echo "  sudo cp $BACKUP_DIR/Caddyfile.backup $CADDYFILE_PATH"
echo "  sudo systemctl restart caddy"
echo ""
echo "=== Migration Complete ==="

# Cleanup old domain from any other configuration files
echo ""
echo "=== Checking for Old Domain References ==="
echo "Searching for remaining references to $OLD_DOMAIN..."

# Check common configuration locations
CONFIG_LOCATIONS=(
    "/etc/systemd/system"
    "/etc/strfry"
    "/usr/local/bin"
    "/var/log"
)

for location in "${CONFIG_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        echo "Checking $location..."
        if grep -r "$OLD_DOMAIN" "$location" 2>/dev/null | head -5; then
            echo "⚠️  Found references to $OLD_DOMAIN in $location"
            echo "   Please review and update these files manually if needed"
        fi
    fi
done

echo ""
echo "Domain migration script completed successfully!"
echo "New domain: https://$NEW_DOMAIN"
