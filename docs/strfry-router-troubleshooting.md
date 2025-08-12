# Strfry Router Sync Troubleshooting Guide

## Issue: Events Not Syncing Between Discovery Relays

If you're experiencing issues where new events (like kind 10002) published to one discovery relay (e.g., `discovery.us.nostria.app`) are not appearing on other discovery relays (e.g., `discovery.af.nostria.app`, `discovery.eu.nostria.app`), this guide will help you troubleshoot and fix the problem.

## Quick Diagnosis

Run the diagnostic script to identify the issue:

```bash
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/diagnose-strfry-router-sync.sh | sudo bash
```

## Common Issues and Solutions

### 1. Missing Discovery Relay Sync Configuration

**Symptoms:**
- Router configuration only shows external relays (purplepag.es, damus, primal)
- No `nostria_eu`, `nostria_us`, or `nostria_af` entries in router config

**Quick Fix:**
```bash
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/fix-strfry-router-sync.sh | sudo bash
```

**Manual Fix:**
1. Check router configuration:
   ```bash
   sudo cat /etc/strfry/strfry-router.conf
   ```

2. If missing discovery relay entries, recreate the configuration:
   ```bash
   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash
   ```

### 2. Router Service Not Running

**Check Status:**
```bash
sudo systemctl status strfry-router
```

**Fix:**
```bash
sudo systemctl start strfry-router
sudo systemctl enable strfry-router
```

### 3. Network Connectivity Issues

**Test Connectivity:**
```bash
# Test HTTPS connectivity
curl -v https://discovery.eu.nostria.app/health
curl -v https://discovery.us.nostria.app/health
curl -v https://discovery.af.nostria.app/health

# Test WebSocket (manual)
wscat -c wss://discovery.eu.nostria.app/
```

**Fix Connectivity:**
- Verify DNS resolution: `nslookup discovery.eu.nostria.app`
- Check firewall rules: `sudo ufw status`
- Ensure outbound HTTPS (443) is allowed

### 4. Main Strfry Service Issues

**Check Main Service:**
```bash
sudo systemctl status strfry
sudo journalctl -u strfry -n 20
```

**Fix:**
```bash
sudo systemctl restart strfry
```

### 5. Configuration Syntax Errors

**Test Configuration:**
```bash
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf router /etc/strfry/strfry-router.conf --help
```

**View Router Logs:**
```bash
sudo journalctl -u strfry-router -f
```

## Expected Router Configuration

A properly configured discovery relay should have entries like this in `/etc/strfry/strfry-router.conf`:

```toml
streams {
    # Two-way sync with other Nostria Discovery Relays
    nostria_eu {
        dir = "both"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://discovery.eu.nostria.app/"]
        reconnectDelaySeconds = 30
    }
    
    nostria_us {
        dir = "both"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://discovery.us.nostria.app/"]
        reconnectDelaySeconds = 30
    }
    
    nostria_af {
        dir = "both"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://discovery.af.nostria.app/"]
        reconnectDelaySeconds = 30
    }
    
    # Two-way sync with Nostria Index Relay
    nostria_index {
        dir = "both"
        filter = { "kinds": [3, 10002] }
        urls = ["wss://index.eu.nostria.app/"]
        reconnectDelaySeconds = 30
    }
    
    # External relays...
    purplepages { ... }
    damus { ... }
    primal { ... }
}
```

**Note:** The current region's discovery relay should NOT be included (to avoid self-sync).

## Manual Sync Testing

Test manual sync to verify connectivity:

```bash
# Test sync with EU discovery relay (from non-EU region)
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf sync "wss://discovery.eu.nostria.app/" --filter '{"kinds":[10002]}' --limit 5

# Check if events were received
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf scan '{"kinds":[10002],"limit":10}'
```

## Monitoring Sync Activity

### Real-time Monitoring
```bash
# Watch router logs
sudo journalctl -u strfry-router -f

# Run monitoring script
sudo /usr/local/bin/strfry-router-monitor.sh
```

### Event Count Verification
```bash
# Count current events
strfry scan '{"kinds":[3]}' | wc -l      # Contact lists
strfry scan '{"kinds":[10002]}' | wc -l  # Relay lists

# Show recent kind 10002 events
strfry scan '{"kinds":[10002],"limit":5}'
```

## Complete Reconfiguration

If issues persist, completely reconfigure the router:

```bash
# Stop router service
sudo systemctl stop strfry-router

# Backup and remove current config
sudo mv /etc/strfry/strfry-router.conf /etc/strfry/strfry-router.conf.backup

# Remove router service
sudo systemctl disable strfry-router
sudo rm -f /etc/systemd/system/strfry-router.service

# Reconfigure from scratch
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash

# Run initial sync
curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash
```

## Performance Tuning

For high-traffic relays, add performance settings to `/etc/strfry/strfry-router.conf`:

```toml
# At the end of the file
maxConcurrentConnections = 10
reconnectDelaySeconds = 5
maxEventsPerSecond = 100
```

Then restart the router:
```bash
sudo systemctl restart strfry-router
```

## Log Analysis

### Router Logs
```bash
# Recent router activity
sudo journalctl -u strfry-router --since "1 hour ago"

# Filter for sync activity
sudo journalctl -u strfry-router | grep -i -E "(sync|connect|error)"
```

### Main Relay Logs
```bash
# Check for errors
sudo journalctl -u strfry --since "1 hour ago" | grep -i error

# Check for new events
sudo journalctl -u strfry | grep -i "kind.*10002"
```

## Verification Steps

After applying fixes:

1. **Verify Configuration:**
   ```bash
   sudo cat /etc/strfry/strfry-router.conf | grep -A 10 nostria_
   ```

2. **Verify Services:**
   ```bash
   sudo systemctl status strfry strfry-router
   ```

3. **Test Event Sync:**
   - Publish a test kind 10002 event to one discovery relay
   - Check if it appears on other discovery relays within 30 seconds
   - Monitor logs during the test

4. **Check Event Counts:**
   ```bash
   # Run on each discovery relay
   strfry scan '{"kinds":[10002]}' | wc -l
   ```

The event counts should be similar across all discovery relays if sync is working properly.

## Getting Help

If issues persist:

1. Run the diagnostic script and save output
2. Check recent logs for errors
3. Verify network connectivity between discovery relays
4. Consider firewall or DNS issues
5. Review strfry documentation for router-specific issues

## Summary

The most common cause of sync issues is **missing discovery relay entries** in the router configuration. The quick fix script should resolve this in most cases. If manual intervention is needed, ensure all discovery relays (except the current one) are configured with `dir = "both"` for bidirectional sync.
