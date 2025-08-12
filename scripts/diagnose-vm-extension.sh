#!/bin/bash

echo "=== Azure VM Extension Diagnostics ==="
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo

# Check if we're running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script should be run as root (or with sudo)"
    exit 1
fi

echo "=== System Information ==="
echo "OS: $(lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME)"
echo "Kernel: $(uname -r)"
echo "Architecture: $(uname -m)"
echo "Uptime: $(uptime)"
echo

echo "=== Network Connectivity ==="
echo "Public IP: $(curl -s ifconfig.me 2>/dev/null || echo "Unable to determine")"
echo "DNS Resolution test:"
nslookup github.com || echo "❌ DNS resolution failed"
echo "Internet connectivity test:"
curl -s --max-time 10 https://github.com && echo "✅ GitHub accessible" || echo "❌ GitHub not accessible"
echo

echo "=== Disk Information ==="
echo "Available disks:"
lsblk
echo
echo "Mounted filesystems:"
df -h
echo
echo "Disk usage:"
du -sh /var/log/* 2>/dev/null | head -10
echo

echo "=== Azure Extension Logs ==="
EXTENSION_LOG_DIR="/var/log/azure"
if [ -d "$EXTENSION_LOG_DIR" ]; then
    echo "Azure extension logs found:"
    find "$EXTENSION_LOG_DIR" -type f -name "*.log" | head -10
    echo
    
    echo "Recent extension logs:"
    find "$EXTENSION_LOG_DIR" -type f -name "*.log" -exec tail -20 {} \; 2>/dev/null | tail -50
else
    echo "❌ Azure extension log directory not found"
fi
echo

echo "=== Custom Script Extension Status ==="
WAAGENT_LOG="/var/log/waagent.log"
if [ -f "$WAAGENT_LOG" ]; then
    echo "Checking waagent.log for extension activity:"
    grep -i "custom\|script\|extension" "$WAAGENT_LOG" | tail -20
else
    echo "❌ waagent.log not found"
fi
echo

echo "=== VM Setup Script Logs ==="
VM_SETUP_LOG="/var/log/vm-setup.log"
if [ -f "$VM_SETUP_LOG" ]; then
    echo "VM setup log found. Last 50 lines:"
    tail -50 "$VM_SETUP_LOG"
else
    echo "❌ VM setup log not found at $VM_SETUP_LOG"
fi
echo

echo "=== Process Information ==="
echo "Running processes related to setup:"
ps aux | grep -E "(apt|dpkg|wget|curl|git|make|gcc)" | grep -v grep
echo

echo "=== Package Manager Status ==="
echo "APT lock status:"
lsof /var/lib/dpkg/lock-frontend 2>/dev/null && echo "❌ APT is locked" || echo "✅ APT is available"
echo
echo "Recent package manager activity:"
tail -20 /var/log/apt/history.log 2>/dev/null || echo "No apt history found"
echo

echo "=== Memory and CPU Usage ==="
free -h
echo
echo "CPU usage:"
top -bn1 | head -20
echo

echo "=== Service Status ==="
echo "Checking for strfry and caddy services:"
systemctl status strfry --no-pager 2>/dev/null || echo "strfry service not found"
systemctl status caddy --no-pager 2>/dev/null || echo "caddy service not found"
echo

echo "=== Network Ports ==="
echo "Listening ports:"
netstat -tlnp 2>/dev/null || ss -tlnp
echo

echo "=== Recent System Logs ==="
echo "Recent system messages:"
journalctl --no-pager -n 20 --since "1 hour ago"
echo

echo "=== Recommendations ==="
if [ ! -f "$VM_SETUP_LOG" ]; then
    echo "🔧 VM setup script hasn't created its log file. The extension may not have started."
    echo "   Try running the setup script manually:"
    echo "   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/vm-setup-robust.sh | sudo bash"
fi

if lsof /var/lib/dpkg/lock-frontend 2>/dev/null; then
    echo "🔧 Package manager is locked. Wait for current operations to complete or reboot the VM."
fi

if ! curl -s --max-time 10 https://github.com > /dev/null; then
    echo "🔧 No internet connectivity. Check Azure network security groups and VM networking."
fi

echo
echo "=== Diagnostics Complete ==="
