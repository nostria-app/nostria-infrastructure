# Strfry Router Sync Configuration for Discovery Relay

This document explains how to configure strfry to sync only event kinds 3 (contact lists) and 10002 (relay lists) between multiple Nostr relays.

## Overview

The configuration sets up:
- **Two-way sync** with `wss://purplepag.es/` (both upload and download)
- **One-way sync** from `wss://relay.damus.io/` (download only)
- **One-way sync** from `wss://relay.primal.net/` (download only)

Only event kinds 3 and 10002 are synchronized, ensuring efficient bandwidth usage and focused data replication.

## Architecture

```
Your Discovery Relay
         ↕ (both directions)
    wss://purplepag.es/
         
         ↓ (download only)
    wss://relay.damus.io/
         
         ↓ (download only)
    wss://relay.primal.net/
```

## Installation Steps

### Step 1: Deploy Discovery Relay VM

First, ensure your discovery relay VM is deployed and running:

```powershell
# From your local machine
.\scripts\deploy-discovery-relay-vm.ps1 -resourceGroupName "nostria-eu-discovery" -location "West Europe"
```

### Step 2: Setup Strfry Router

SSH into your deployed VM and run the router setup script:

```bash
# SSH into your VM
ssh azureuser@your-vm-ip

# Run the router setup script
sudo curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash
```

Alternatively, if you have access to the setup script locally:

```bash
sudo /path/to/setup-strfry-router.sh
```

## Configuration Files

### Router Configuration (`/etc/strfry/strfry-router.conf`)

```toml
# Connection timeout in seconds
connectionTimeout = 20

# Logging configuration
logLevel = "info"

# Stream configurations
streams {
    # Two-way sync with purplepag.es
    purplepages {
        dir = "both"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://purplepag.es/"]
    }
    
    # One-way sync (down only) from Damus relay
    damus {
        dir = "down"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://relay.damus.io/"]
    }
    
    # One-way sync (down only) from Primal relay
    primal {
        dir = "down"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://relay.primal.net/"]
    }
}
```

### SystemD Service (`/etc/systemd/system/strfry-router.service`)

The router runs as a separate systemd service that depends on the main strfry relay service.

## Monitoring and Management

### Check Service Status

```bash
# Check if both services are running
sudo systemctl status strfry
sudo systemctl status strfry-router

# View real-time logs
sudo journalctl -u strfry-router -f
sudo journalctl -u strfry -f
```

### Monitor Sync Activity

```bash
# Run the monitoring script
sudo /usr/local/bin/strfry-router-monitor.sh

# Check event counts in database
strfry scan '{"kinds":[3]}' | wc -l      # Contact lists
strfry scan '{"kinds":[10002]}' | wc -l  # Relay lists
```

### Manual Sync Commands

```bash
# Manual one-time sync (as strfry user)
sudo -u strfry strfry sync wss://purplepag.es/ --filter '{"kinds":[3,10002]}'
sudo -u strfry strfry sync wss://relay.damus.io/ --filter '{"kinds":[3,10002]}' --dir down
sudo -u strfry strfry sync wss://relay.primal.net/ --filter '{"kinds":[3,10002]}' --dir down
```

## Event Kinds Explained

- **Kind 3 (Contact Lists)**: User follow lists and metadata about followed users
- **Kind 10002 (Relay Lists)**: User's preferred relay lists for reading/writing

These kinds are essential for discovery services as they help users find:
1. Who to follow (contact lists)
2. Which relays to connect to (relay lists)

## Security Considerations

### Network Security
- Router runs as `strfry` user with limited privileges
- Uses read-only paths where possible
- Network connections use WSS (encrypted WebSocket)

### Event Validation
- Events are validated before storage
- Signatures are verified by strfry
- Optional plugin validation can be enabled

### Resource Limits
- File descriptor limits configured for high concurrency
- Connection timeouts prevent hanging connections
- Restart policies handle network failures gracefully

## Troubleshooting

### Router Won't Start

1. Check main strfry service is running:
   ```bash
   sudo systemctl status strfry
   ```

2. Check configuration syntax:
   ```bash
   sudo -u strfry strfry router /etc/strfry/strfry-router.conf --test
   ```

3. Check logs for errors:
   ```bash
   sudo journalctl -u strfry-router --no-pager -n 50
   ```

### No Events Being Synced

1. Check network connectivity:
   ```bash
   curl -I https://purplepag.es/
   curl -I https://relay.damus.io/
   curl -I https://relay.primal.net/
   ```

2. Verify filter is working:
   ```bash
   strfry scan '{"kinds":[3,10002],"limit":10}'
   ```

3. Check router logs for connection issues:
   ```bash
   sudo journalctl -u strfry-router -f
   ```

### High Resource Usage

1. Monitor connection count:
   ```bash
   ss -tuln | grep -E "(7777|443)" | wc -l
   ```

2. Check database size:
   ```bash
   du -sh /var/lib/strfry/
   ```

3. Review event retention policy in `/etc/strfry/strfry.conf`

## Performance Tuning

### For High-Volume Relays

Add these settings to your router configuration:

```toml
# Maximum concurrent connections per stream
maxConcurrentConnections = 5

# Reconnection delay
reconnectDelaySeconds = 5

# Rate limiting
maxEventsPerSecond = 50
```

### Database Optimization

1. Enable periodic compaction:
   ```bash
   # Add to crontab
   0 2 * * 0 /usr/local/bin/strfry compact /var/lib/strfry/db/data.mdb.compacted && mv /var/lib/strfry/db/data.mdb.compacted /var/lib/strfry/db/data.mdb
   ```

2. Monitor disk space:
   ```bash
   df -h /var/lib/strfry/
   ```

## Backup and Recovery

### Database Backup

```bash
# Create backup
sudo -u strfry strfry export --fried > /backup/strfry-backup-$(date +%Y%m%d).jsonl

# Restore from backup
sudo -u strfry strfry import --fried < /backup/strfry-backup-20241207.jsonl
```

### Configuration Backup

```bash
# Backup configuration files
sudo tar czf /backup/strfry-config-$(date +%Y%m%d).tar.gz /etc/strfry/ /etc/systemd/system/strfry*
```

## Scaling Considerations

### Multiple Regions

For multi-region deployments, consider:
1. Each region has its own discovery relay
2. Inter-region sync between discovery relays
3. Regional relay lists in event kind 10002

### Load Balancing

For high availability:
1. Deploy multiple discovery relay VMs
2. Use Azure Load Balancer for distribution
3. Configure shared storage for database (optional)

## Support

For issues with this configuration:
1. Check the logs: `sudo journalctl -u strfry-router -f`
2. Review strfry documentation: https://github.com/hoytech/strfry
3. Monitor relay health: `/usr/local/bin/strfry-router-monitor.sh`
