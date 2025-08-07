#!/bin/bash
# Comprehensive debugging script for Caddy TLS certificate issues
# Run this on the VM to diagnose certificate problems

echo "🔍 Nostria Discovery Relay TLS Certificate Debug Tool"
echo "=================================================="
echo "Date: $(date)"
echo ""

# Determine the expected domain
REGION=$(hostname | grep -o '[a-z][a-z]' | head -n1 || echo "eu")
EXPECTED_DOMAIN="index.${REGION}.nostria.app"
echo "🎯 Expected Domain: $EXPECTED_DOMAIN"
echo ""

# 1. Check VM public IP
echo "1️⃣  VM Network Information"
echo "-------------------------"
VM_PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "Unable to determine")
VM_PRIVATE_IP=$(hostname -I | awk '{print $1}')
echo "VM Public IP:  $VM_PUBLIC_IP"
echo "VM Private IP: $VM_PRIVATE_IP"
echo ""

# 2. Check DNS resolution
echo "2️⃣  DNS Resolution Check"
echo "------------------------"
RESOLVED_IP=$(dig +short $EXPECTED_DOMAIN 2>/dev/null || echo "DNS resolution failed")
echo "Domain: $EXPECTED_DOMAIN"
echo "Resolves to: $RESOLVED_IP"

if [ "$VM_PUBLIC_IP" = "$RESOLVED_IP" ]; then
    echo "✅ DNS correctly points to this VM"
    DNS_OK=true
else
    echo "❌ DNS MISMATCH! This is likely the cause of certificate issues."
    echo "   Action needed: Update DNS records to point $EXPECTED_DOMAIN to $VM_PUBLIC_IP"
    DNS_OK=false
fi
echo ""

# 3. Check Caddy service status
echo "3️⃣  Caddy Service Status"
echo "------------------------"
if systemctl is-active --quiet caddy; then
    echo "✅ Caddy service is running"
    CADDY_RUNNING=true
else
    echo "❌ Caddy service is not running"
    echo "   Action: sudo systemctl start caddy"
    CADDY_RUNNING=false
fi

if systemctl is-enabled --quiet caddy; then
    echo "✅ Caddy service is enabled"
else
    echo "⚠️  Caddy service is not enabled for auto-start"
    echo "   Action: sudo systemctl enable caddy"
fi
echo ""

# 4. Check network ports
echo "4️⃣  Network Port Status"
echo "----------------------"
if ss -ln | grep -q ":80.*LISTEN"; then
    echo "✅ Port 80 (HTTP) is listening"
else
    echo "❌ Port 80 (HTTP) is not listening"
fi

if ss -ln | grep -q ":443.*LISTEN"; then
    echo "✅ Port 443 (HTTPS) is listening"
else
    echo "❌ Port 443 (HTTPS) is not listening"
fi

if ss -ln | grep -q ":7777.*LISTEN"; then
    echo "✅ Port 7777 (strfry) is listening"
else
    echo "❌ Port 7777 (strfry) is not listening"
fi
echo ""

# 5. Check firewall
echo "5️⃣  Firewall Configuration"
echo "--------------------------"
ufw status | head -20
echo ""

# 6. Test HTTP connectivity
echo "6️⃣  HTTP Connectivity Test"
echo "--------------------------"
if [ "$DNS_OK" = "true" ]; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://$EXPECTED_DOMAIN/.well-known/acme-challenge/test 2>/dev/null || echo "000")
    echo "HTTP test status: $HTTP_STATUS"
    if [ "$HTTP_STATUS" = "404" ] || [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ HTTP connectivity working (404 expected for missing challenge)"
    else
        echo "❌ HTTP connectivity issue (status: $HTTP_STATUS)"
    fi
else
    echo "⏭️  Skipping HTTP test due to DNS issues"
fi
echo ""

# 7. Check HTTPS certificate
echo "7️⃣  HTTPS Certificate Status"
echo "----------------------------"
if [ "$DNS_OK" = "true" ]; then
    CERT_INFO=$(echo | openssl s_client -connect $EXPECTED_DOMAIN:443 -servername $EXPECTED_DOMAIN 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "Certificate check failed")
    
    if echo "$CERT_INFO" | grep -q "subject="; then
        echo "✅ Certificate is present:"
        echo "$CERT_INFO"
        
        # Check if certificate is valid
        if echo | openssl s_client -connect $EXPECTED_DOMAIN:443 -servername $EXPECTED_DOMAIN 2>/dev/null | openssl x509 -noout -checkend 86400 >/dev/null 2>&1; then
            echo "✅ Certificate is valid and not expiring within 24 hours"
        else
            echo "⚠️  Certificate may be expired or expiring soon"
        fi
    else
        echo "❌ No valid certificate found"
        echo "Raw certificate check result: $CERT_INFO"
    fi
else
    echo "⏭️  Skipping certificate test due to DNS issues"
fi
echo ""

# 8. Check Caddy configuration
echo "8️⃣  Caddy Configuration"
echo "----------------------"
if [ -f "/etc/caddy/Caddyfile" ]; then
    echo "✅ Caddyfile exists"
    echo "Domain in Caddyfile:"
    grep -E "^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" /etc/caddy/Caddyfile | head -5
    
    # Validate configuration
    if /usr/local/bin/caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        echo "✅ Caddyfile syntax is valid"
    else
        echo "❌ Caddyfile syntax error:"
        /usr/local/bin/caddy validate --config /etc/caddy/Caddyfile
    fi
else
    echo "❌ Caddyfile not found at /etc/caddy/Caddyfile"
fi
echo ""

# 9. Check recent Caddy logs
echo "9️⃣  Recent Caddy Logs (Last 20 lines)"
echo "-------------------------------------"
journalctl -u caddy --no-pager -n 20 | grep -E "(error|warn|certificate|tls|acme)" || echo "No certificate-related log entries found"
echo ""

# 10. Caddy certificate information (if available)
echo "🔟 Caddy Internal Certificate Info"
echo "----------------------------------"
if [ "$CADDY_RUNNING" = "true" ]; then
    CERT_LIST=$(curl -s http://localhost:2019/config/apps/tls/certificates 2>/dev/null || echo "Failed to get certificate list")
    if echo "$CERT_LIST" | grep -q "$EXPECTED_DOMAIN"; then
        echo "✅ Certificate found in Caddy's internal store"
        echo "$CERT_LIST" | jq --arg domain "$EXPECTED_DOMAIN" '.[] | select(.names[] == $domain) | {names: .names, not_after: .not_after}' 2>/dev/null || echo "Certificate details available but jq not installed"
    else
        echo "❌ No certificate found in Caddy's internal store for $EXPECTED_DOMAIN"
    fi
else
    echo "⏭️  Cannot check internal certificates (Caddy not running)"
fi
echo ""

# Summary and recommendations
echo "📋 Summary and Recommendations"
echo "==============================="

if [ "$DNS_OK" = "false" ]; then
    echo "❌ PRIMARY ISSUE: DNS not pointing to this VM"
    echo "   🔧 SOLUTION: Update DNS records:"
    echo "      - Create/Update A record: $EXPECTED_DOMAIN → $VM_PUBLIC_IP"
    echo "      - Wait 5-15 minutes for DNS propagation"
    echo "      - Re-run this script to verify"
    echo ""
fi

if [ "$CADDY_RUNNING" = "false" ]; then
    echo "❌ ISSUE: Caddy service not running"
    echo "   🔧 SOLUTION: sudo systemctl start caddy && sudo systemctl enable caddy"
    echo ""
fi

if [ "$DNS_OK" = "true" ] && [ "$CADDY_RUNNING" = "true" ]; then
    echo "✅ Basic setup looks good!"
    echo "   📝 To force certificate renewal: sudo systemctl reload caddy"
    echo "   📝 To watch certificate process: sudo journalctl -u caddy -f"
    echo "   📝 To debug: sudo /usr/local/bin/caddy run --config /etc/caddy/Caddyfile --debug"
fi

# Optional certutil fix
echo ""
echo "🔧 Optional: Fix certutil warning"
echo "================================"
if ! command -v certutil >/dev/null 2>&1; then
    echo "📦 To fix the certutil warning, run:"
    echo "   sudo apt update && sudo apt install libnss3-tools"
    echo "   sudo systemctl restart caddy"
else
    echo "✅ certutil is already installed"
fi

echo ""
echo "🏁 Debug scan complete!"
echo ""
echo "💡 Quick fixes to try:"
echo "   1. Fix DNS if needed (see above)"
echo "   2. sudo systemctl restart caddy"
echo "   3. Wait 2-3 minutes and test: curl -I https://$EXPECTED_DOMAIN/health"
echo "   4. If still failing, run Caddy in debug mode (see above)"
