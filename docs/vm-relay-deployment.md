# Nostria VM Relay Deployment

This directory contains the infrastructure and configuration for deploying Nostria relay servers on dedicated Azure VMs using strfry and Caddy.

## Check logs

ssh azureuser@<VM-PUBLIC-IP>

# Check strfry status
sudo systemctl status strfry

# Check if strfry is listening on port 7777
sudo ss -tulpn | grep 7777

# Check if Caddy is running and listening on port 443
sudo systemctl status caddy
sudo ss -tulpn | grep 443

# Run the health check
/usr/local/bin/strfry-health-check.sh

## Overview

The VM relay deployment provides:

- **Dedicated VM infrastructure** for high-performance relay operations
- **strfry** - A high-performance nostr relay implementation in C++
- **Caddy** - Automatic HTTPS/TLS certificate management and reverse proxy
- **Ubuntu 22.04 LTS** - Stable, secure Linux foundation
- **Monitoring and logging** - Built-in health checks and structured logging

## Architecture

```
Internet → Azure Load Balancer → Caddy (Port 443/80) → strfry (Port 7777)
                                  ↓
                            TLS Termination & Proxy
                                  ↓
                            Monitoring (Port 8080)
```

## Deployment

### Prerequisites

1. **Azure CLI** installed and authenticated
2. **SSH key pair** generated:
   ```powershell
   ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\id_rsa
   ```

### Quick Start

1. **Deploy VM Relay:**
   ```powershell
   ./scripts/deploy-vm-relay.ps1 -Region "eu" -VmRelayCount 1
   ```

2. **Configure DNS:**
   - Point `ribo.[region].nostria.app` to the VM's public IP
   - For multiple VMs, point `rilo.[region].nostria.app`, `rifu.[region].nostria.app`, etc. to their respective IPs
   - Wait for DNS propagation (5-15 minutes)

3. **Verify Deployment:**
   ```bash
   # Test WebSocket connection (for EU region example)
   wscat -c wss://ribo.eu.nostria.app
   
   # Check relay info (NIP-11)
   curl https://ribo.eu.nostria.app/status
   ```

### Advanced Deployment

For production deployments with custom settings:

```powershell
./scripts/deploy-vm-relay.ps1 `
    -Location "westeurope" `
    -Region "eu" `
    -VmSize "Standard_D2s_v3" `
    -VmRelayCount 2 `
    -SshPublicKeyPath "C:\path\to\your\public\key.pub"
```

**Note:** This will create VMs named `nostria-eu-ribo-vm` and `nostria-eu-rilo-vm` in resource group `nostria-eu-relays`.

## Configuration

### VM Specifications

| Component | Default | Production Recommended |
|-----------|---------|----------------------|
| VM Size | Standard_B2s | Standard_D2s_v3 |
| OS Disk | 30GB Premium SSD | 30GB Premium SSD |
| Memory | 4GB | 8GB |
| vCPUs | 2 | 2-4 |

### Network Configuration

- **Virtual Network:** 10.0.0.0/16
- **VM Subnet:** 10.0.1.0/24
- **NSG Rules:**
  - SSH (22) - Management access
  - HTTP (80) - Caddy redirect
  - HTTPS (443) - Main relay traffic
  - strfry (7777) - Internal only

### strfry Configuration

Key strfry settings optimized for VM deployment:

```conf
# Database location
db = "/var/lib/strfry/db"

# Network binding (localhost only, behind Caddy)
relay {
    bind = "127.0.0.1"
    port = 7777
    maxWebsocketConnections = 1000
}

# Event retention
retention = [
    { kinds = [0, 3], count = 1 },      # Profile events
    { kinds = [1], time = 2592000 },    # Text notes (30 days)
    { kinds = [7], time = 604800 },     # Reactions (7 days)
    { time = 604800 }                   # Default (7 days)
]
```

### Caddy Configuration

Caddy provides:

- **Automatic HTTPS** with Let's Encrypt certificates
- **WebSocket proxying** to strfry
- **Security headers** for enhanced protection
- **Health checks** and monitoring endpoints
- **Rate limiting** for abuse protection

## Management

### Accessing the VM

```bash
# SSH to the VM
ssh azureuser@<VM-PUBLIC-IP>

# Check service status
sudo systemctl status strfry
sudo systemctl status caddy

# View logs
sudo journalctl -u strfry -f
sudo journalctl -u caddy -f
```

### Health Monitoring

```bash
# Run health check script
/usr/local/bin/strfry-health-check.sh

# Check relay metrics
curl http://localhost:8080/strfry/

# Check Caddy metrics
curl http://localhost:8080/metrics
```

### Configuration Updates

1. **Update strfry config:**
   ```bash
   sudo nano /etc/strfry/strfry.conf
   sudo systemctl restart strfry
   ```

2. **Update Caddy config:**
   ```bash
   sudo nano /etc/caddy/Caddyfile
   sudo systemctl reload caddy
   ```

### Database Management

```bash
# Export relay data
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export > backup.jsonl

# Import relay data
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf import < backup.jsonl

# Compact database
sudo systemctl stop strfry
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf compact - > /var/lib/strfry/db/data.mdb.compacted
sudo -u strfry mv /var/lib/strfry/db/data.mdb.compacted /var/lib/strfry/db/data.mdb
sudo systemctl start strfry
```

## Security

### Firewall Configuration

The deployment includes ufw firewall with restrictive rules:

```bash
# View firewall status
sudo ufw status

# Allow additional services if needed
sudo ufw allow from <trusted-ip> to any port <port>
```

### Security Headers

Caddy automatically applies security headers:

- `Strict-Transport-Security` - HSTS enforcement
- `X-Content-Type-Options` - MIME type sniffing protection
- `X-Frame-Options` - Clickjacking protection
- `Content-Security-Policy` - XSS protection

### Updates and Maintenance

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update strfry (manual process)
cd /tmp
git clone https://github.com/hoytech/strfry
cd strfry
git submodule update --init
make setup-golpe
make -j$(nproc)
sudo systemctl stop strfry
sudo cp strfry /usr/local/bin/
sudo systemctl start strfry

# Update Caddy (automatic via apt)
sudo apt update && sudo apt upgrade caddy
```

## Monitoring and Alerts

### Built-in Monitoring

- **Health check script** runs every 5 minutes via cron
- **Systemd status** monitoring for service failures
- **Log rotation** for disk space management
- **Metrics endpoints** for external monitoring systems

### Log Files

| Service | Log Location | Format |
|---------|--------------|--------|
| strfry | `/var/log/strfry/strfry.log` | Structured |
| Caddy | `/var/log/caddy/access.log` | JSON |
| System | `/var/log/syslog` | Text |
| Health | `/var/log/strfry-health.log` | Text |

### External Monitoring

Configure your monitoring system to check:

- **HTTPS endpoint:** `https://ribo.eu.nostria.app/health`
- **VM metrics:** Via Azure Monitor
- **Service status:** Via custom scripts or Azure Monitor

## Troubleshooting

### Common Issues

1. **Certificate not obtaining:**
   ```bash
   # Check Caddy logs
   sudo journalctl -u caddy -f
   
   # Verify DNS resolution
   nslookup ribo.eu.nostria.app
   ```

2. **strfry not accepting connections:**
   ```bash
   # Check if strfry is listening
   sudo netstat -tlnp | grep 7777
   
   # Check strfry logs
   sudo journalctl -u strfry -f
   ```

3. **High memory usage:**
   ```bash
   # Check strfry database size
   sudo du -sh /var/lib/strfry/db/
   
   # Consider database compaction
   # (See Database Management section)
   ```

### Performance Tuning

For high-traffic deployments:

1. **Increase VM size** to Standard_D4s_v3 or higher
2. **Adjust strfry settings:**
   ```conf
   maxWebsocketConnections = 2000
   maxreaders = 512
   ```
3. **Enable strfry compression:**
   ```conf
   compression = true
   ```
4. **Optimize retention policy** for your use case

## Scaling

### Horizontal Scaling

Deploy multiple VM relays:

```powershell
./scripts/deploy-vm-relay.ps1 -VmRelayCount 3
```

Then configure a load balancer or use DNS round-robin.

### Vertical Scaling

Update VM size in the Bicep template and redeploy:

```bicep
param vmSize string = 'Standard_D4s_v3'
```

## Support

For issues with:

- **Infrastructure deployment:** Check Azure portal and logs
- **strfry configuration:** See [strfry documentation](https://github.com/hoytech/strfry)
- **Caddy configuration:** See [Caddy documentation](https://caddyserver.com/docs/)
- **Nostria-specific issues:** Contact admin@nostria.app

## Files Structure

```
bicep/
├── vm-relay.bicep                 # Main VM deployment template
├── vm-relay.bicepparam           # Parameters file
└── modules/
    ├── virtual-machine.bicep     # VM resource module
    ├── virtual-network.bicep     # VNet module
    └── network-security-group.bicep # NSG module

config/vm-relay/
├── strfry.conf                   # strfry configuration template
└── Caddyfile                     # Caddy configuration template

scripts/
├── deploy-vm-relay.ps1           # Deployment script
└── vm-setup.sh                   # VM initialization script
```
