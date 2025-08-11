#!/bin/bash
# DNS Checker for Discovery Relay
# This script checks DNS propagation from multiple sources

echo "=== DNS Propagation Checker ==="
echo "Date: $(date)"
echo ""

# Auto-detect domain or ask user
HOSTNAME=$(hostname)
REGION=$(echo "$HOSTNAME" | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')

if [ -z "$REGION" ]; then
    echo "Could not auto-detect region from hostname: $HOSTNAME"
    echo "Please enter the region (e.g., eu, us, af):"
    read -r REGION
fi

DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Checking DNS for: $DISCOVERY_DOMAIN"
echo ""

# Get VM's external IP
echo "Getting VM external IP..."
EXTERNAL_IP=$(curl -s --connect-timeout 10 ifconfig.me 2>/dev/null)
if [ -z "$EXTERNAL_IP" ]; then
    echo "ERROR: Could not determine external IP"
    exit 1
fi
echo "VM External IP: $EXTERNAL_IP"
echo ""

# Check with multiple public DNS servers
echo "=== DNS Resolution Tests ==="
DNS_SERVERS=(
    "8.8.8.8:Google"
    "1.1.1.1:Cloudflare"
    "208.67.222.222:OpenDNS"
    "9.9.9.9:Quad9"
)

CORRECT_COUNT=0
TOTAL_COUNT=${#DNS_SERVERS[@]}

for dns_entry in "${DNS_SERVERS[@]}"; do
    dns_server=$(echo "$dns_entry" | cut -d: -f1)
    dns_name=$(echo "$dns_entry" | cut -d: -f2)
    
    echo -n "Testing $dns_name ($dns_server): "
    
    RESOLVED_IP=$(dig @$dns_server +short $DISCOVERY_DOMAIN 2>/dev/null | tail -1)
    
    if [ -z "$RESOLVED_IP" ]; then
        echo "❌ No response"
    elif [ "$RESOLVED_IP" = "$EXTERNAL_IP" ]; then
        echo "✅ Correct ($RESOLVED_IP)"
        ((CORRECT_COUNT++))
    else
        echo "❌ Wrong IP ($RESOLVED_IP)"
    fi
done

# Check local system DNS
echo -n "Testing Local DNS: "
LOCAL_RESOLVED=$(nslookup $DISCOVERY_DOMAIN 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' 2>/dev/null || echo "")
if [ -z "$LOCAL_RESOLVED" ]; then
    echo "❌ No response"
elif [ "$LOCAL_RESOLVED" = "$EXTERNAL_IP" ]; then
    echo "✅ Correct ($LOCAL_RESOLVED)"
else
    echo "❌ Wrong IP ($LOCAL_RESOLVED)"
fi

echo ""
echo "=== DNS Summary ==="
echo "Domain: $DISCOVERY_DOMAIN"
echo "Expected IP: $EXTERNAL_IP"
echo "Correct DNS servers: $CORRECT_COUNT/$TOTAL_COUNT"

if [ $CORRECT_COUNT -eq $TOTAL_COUNT ]; then
    echo "🎉 DNS is fully propagated and correct!"
    echo "✅ You can safely enable HTTPS now"
elif [ $CORRECT_COUNT -gt 0 ]; then
    echo "⚠ DNS is partially propagated ($CORRECT_COUNT/$TOTAL_COUNT servers correct)"
    echo "⏳ Wait a few more minutes for full propagation"
    echo "ℹ You can try enabling HTTPS, but it might fail initially"
else
    echo "❌ DNS is not propagated or configured incorrectly"
    echo "🔧 Please check your DNS configuration"
    echo ""
    echo "Expected DNS record:"
    echo "  Type: A"
    echo "  Name: discovery.${REGION}"
    echo "  Value: $EXTERNAL_IP"
    echo "  TTL: 300 (5 minutes)"
fi

echo ""
echo "=== Additional Information ==="
echo "Online DNS checker: https://dnschecker.org/#A/$DISCOVERY_DOMAIN"
echo "DNS propagation typically takes 5-30 minutes"
echo ""

# Show current VM network info
echo "VM Network Information:"
echo "  Hostname: $HOSTNAME"
echo "  External IP: $EXTERNAL_IP"
echo "  Internal IP: $(ip route get 8.8.8.8 | grep -oP 'src \K\S+' 2>/dev/null || echo 'unknown')"

echo ""
echo "To enable HTTPS after DNS is correct:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/simple-https-fix.sh | sudo bash"

echo ""
echo "DNS check completed at $(date)"
