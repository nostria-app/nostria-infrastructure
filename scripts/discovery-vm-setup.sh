#!/bin/bash
set -e

# Get force update parameter if provided
FORCE_UPDATE=${1:-"initial"}

# Log all output to a file for debugging
exec > >(tee -a /var/log/discovery-vm-setup.log) 2>&1
echo "Starting Discovery Relay VM setup at $(date) with force update: $FORCE_UPDATE"

# Check if this is a re-run (services already exist)
RERUN=false
if systemctl list-units --full -all | grep -Fq "strfry.service"; then
    echo "Detected existing strfry service - this appears to be a configuration update (force update: $FORCE_UPDATE)"
    RERUN=true
fi

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive

if [ "$RERUN" = "false" ]; then
    # Configure package sources
    echo "Configuring package sources..."
    cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF

    apt-get update || true
    apt-get upgrade -y

    # Setup data disk for strfry database
    echo "Setting up data disk for strfry database..."
    
    # Find the data disk (should be the first unpartitioned disk that's not the OS disk)
    DATA_DISK=$(lsblk -dn -o NAME,SIZE | grep -v "$(lsblk -dn -o NAME | head -n1)" | head -n1 | awk '{print $1}')
    
    if [ -n "$DATA_DISK" ]; then
        echo "Found data disk: /dev/$DATA_DISK"
        
        # Create partition table and partition
        parted /dev/$DATA_DISK --script mklabel gpt
        parted /dev/$DATA_DISK --script mkpart primary ext4 0% 100%
        
        # Format the partition with ext4
        mkfs.ext4 -F /dev/${DATA_DISK}1
        
        # Create mount point
        mkdir -p /var/lib/strfry
        
        # Get UUID for permanent mounting
        DATA_UUID=$(blkid -s UUID -o value /dev/${DATA_DISK}1)
        
        # Add to fstab for permanent mounting
        echo "UUID=$DATA_UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab
        
        # Mount the disk
        mount /var/lib/strfry
        
        echo "Data disk mounted successfully at /var/lib/strfry"
    else
        echo "No additional data disk found, using OS disk for database"
        mkdir -p /var/lib/strfry
    fi
    # Configure proper package sources
    echo "Configuring package sources..."
    cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF

    apt-get update || true
    apt-get upgrade -y
else
    echo "Skipping package sources configuration (rerun detected)"
    apt-get update || true
fi

# Install required packages for strfry compilation
if [ "$RERUN" = "false" ]; then
    echo "Installing build dependencies..."
    apt-get install -y build-essential git wget curl net-tools
    apt-get install -y libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev

    # Verify essential tools are available
    if ! command -v make &> /dev/null; then
        echo "ERROR: make command not found"
        exit 1
    fi

    if ! command -v g++ &> /dev/null; then
        echo "ERROR: g++ command not found"
        exit 1
    fi
else
    echo "Skipping build dependencies installation (rerun detected)"
fi

# Install Caddy using alternative method to avoid GPG issues
if [ "$RERUN" = "false" ] && [ ! -f "/usr/local/bin/caddy" ]; then
    echo "Installing Caddy..."
    # Install Caddy directly from GitHub releases (more reliable for automated environments)
    CADDY_VERSION="2.7.6"
    echo "Downloading Caddy v${CADDY_VERSION}..."
    wget -q "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" -O /tmp/caddy.tar.gz
    cd /tmp
    tar -xzf caddy.tar.gz
    mv caddy /usr/local/bin/
    chmod +x /usr/local/bin/caddy
    rm -f caddy.tar.gz LICENSE README.md

    # Create caddy user and group
    groupadd --system caddy
    useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy

    # Create necessary directories
    mkdir -p /etc/caddy
    mkdir -p /var/log/caddy
    chown -R caddy:caddy /var/lib/caddy
    chown -R caddy:caddy /var/log/caddy

    # Create systemd service for Caddy
    cat > /etc/systemd/system/caddy.service << 'EOF'
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=/usr/local/bin/caddy run --environ --config /etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
else
    echo "Skipping Caddy installation (already exists or rerun detected)"
fi

# Create strfry user
if [ "$RERUN" = "false" ]; then
    echo "Creating strfry user..."
    useradd -r -s /bin/false -d /var/lib/strfry strfry

    # Create directories (after data disk is mounted)
    echo "Creating directories..."
    mkdir -p /var/lib/strfry/db
    mkdir -p /etc/strfry
    mkdir -p /var/log/strfry
    chown -R strfry:strfry /var/lib/strfry /var/log/strfry
else
    echo "Skipping strfry user creation (rerun detected)"
    # Ensure directories exist and have proper ownership
    mkdir -p /var/lib/strfry/db
    mkdir -p /etc/strfry
    mkdir -p /var/log/strfry
    chown -R strfry:strfry /var/lib/strfry /var/log/strfry
fi

# Clone and compile strfry
if [ "$RERUN" = "false" ] && [ ! -f "/usr/local/bin/strfry" ]; then
    echo "Cloning and compiling strfry..."
    cd /tmp
    git clone https://github.com/hoytech/strfry
    cd strfry
    git submodule update --init
    make setup-golpe
    make -j$(nproc)

    # Install strfry binary
    echo "Installing strfry binary..."
    cp strfry /usr/local/bin/
    chmod +x /usr/local/bin/strfry
else
    echo "Skipping strfry compilation (already exists or rerun detected)"
fi

# Create discovery relay specific strfry configuration
echo "Creating/updating discovery relay strfry configuration..."
cat > /etc/strfry/strfry.conf << 'EOF'
##
## strfry relay config for Nostria Discovery Relay VM deployment
##

# Directory that contains the strfry LMDB database (restart required)
db = "/var/lib/strfry/db"

dbParams {
    # Maximum number of threads/processes that can simultaneously have LMDB transactions open (restart required)
    maxreaders = 256

    # Size of mmap() to use when loading LMDB (default is 10TB, does *not* correspond to disk-space used) (restart required)
    mapsize = 10995116277760

    # Disables read-ahead when accessing the LMDB mapping. Reduces IO activity when DB size is larger than RAM. (restart required)
    noReadAhead = false
}

events {
    # Maximum size of normalised JSON, in bytes
    maxEventSize = 65536

    # Events newer than this will be rejected
    rejectEventsNewerThanSeconds = 900

    # Events older than this will be rejected
    rejectEventsOlderThanSeconds = 94608000

    # Ephemeral events older than this will be rejected
    rejectEphemeralEventsOlderThanSeconds = 60

    # Ephemeral events will be deleted from the DB when older than this
    ephemeralEventsLifetimeSeconds = 300

    # Maximum number of tags allowed
    maxNumTags = 2000

    # Maximum size for tag values, in bytes
    maxTagValSize = 1024
}

relay {
    # Interface to listen on. Use 127.0.0.1 to listen only on localhost (for reverse proxy)
    bind = "127.0.0.1"

    # Port to open for the nostr websocket protocol (restart required)
    port = 7777

    # Set OS-limit on maximum number of open files/sockets (if 0, don't attempt to set) (restart required)
    nofiles = 500000

    # HTTP header that contains the client's real IP, before reverse proxying (X-Forwarded-For, etc)
    realIpHeader = "X-Forwarded-For"

    info {
        # NIP-11: Name of this server. Short/descriptive (< 30 characters)
        name = "Nostria Discovery Relay"

        # NIP-11: Detailed plain-text description of relay
        description = "A specialized Nostria discovery relay running on dedicated VM infrastructure with strfry and Caddy. This relay provides discovery and relay listing services for the Nostria network, helping users find and connect to other relays in the network."

        # NIP-11: Administrative nostr pubkey, for contact purposes
        pubkey = "17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515"

        # NIP-11: Alternative contact
        contact = "mailto:admin@nostria.app"

        # NIP-11: List of supported NIPs
        supported_nips = [1, 65]

        # NIP-11: Software information
        software = "git+https://github.com/hoytech/strfry.git"
        version = "latest"

        # NIP-11: Relay limitations
        limitation {
            # Maximum number of concurrent connections
            max_ws_frame_size = 131072
            max_connections = 1000
            max_subscriptions = 20
            max_filters = 100
            max_limit = 5000
            max_subid_length = 100
            max_event_tags = 2000
            max_content_length = 8196
            min_pow_difficulty = 0
            auth_required = false
            payment_required = false
            restricted_writes = false
        }

        # NIP-11: Posting policy URL
        posting_policy = "https://nostria.app/posting-policy"

        # NIP-11: Fees (none for now)
        fees {
            admission = []
            subscription = []
            publication = []
        }
    }

    # Maximum number of websocket connections
    maxWebsocketConnections = 1000

    # Maximum length of per-connection write buffer, in bytes
    maxWebsocketSendBufferSize = 262144

    # Websocket compression is enabled by default; uncomment to disable
    # compression = false

    # Allow all IP addresses (since we're behind Caddy reverse proxy)
    # To restrict access, uncomment and configure:
    # allowedIps = ["0.0.0.0/0"]
}

# Path to custom plugin script (commented out for now)
# plugin = "/etc/strfry/plugins/nostria-discovery-policy.js"

# Enable built-in monitoring webserver (accessible via Caddy)
monitoring {
    bind = "127.0.0.1"
    port = 7778
}

# Event retention policy for discovery relay - keep relay lists and discovery events longer
retention = [
    # Keep contact lists (kind 3) for each pubkey
    {
        kinds = [3]
        count = 1
    },
    # Keep relay list for each pubkey (kind 10002)
    {
        kinds = [10002]
        count = 1
    },
    # Default retention for all other events: 0 days
    {
        time = 0   # 0 days
    }
]

# Ingestion settings
ingestion {
    # Enable/disable event ingestion
    enabled = true
    
    # Maximum number of events to accept per second (rate limiting)
    # maxEventsPerSecond = 100
    
    # Reject events from relays that are known to be problematic
    # blockedRelays = []
    
    # Only accept events from specific relays (if configured)
    # allowedRelays = []
}

# Logging configuration
logging {
    # Log level: trace, debug, info, warn, error
    level = "info"
    
    # Enable structured logging
    structured = true
    
    # Log to file
    file = "/var/log/strfry/strfry.log"
    
    # Rotate log files
    rotate = true
    maxSize = "100MB"
    maxFiles = 10
}

# Performance tuning
performance {
    # Number of worker threads for processing events
    # (0 = auto-detect based on CPU cores)
    workerThreads = 0
    
    # Buffer size for event processing
    eventBufferSize = 1000
    
    # Enable memory-mapped I/O optimizations
    useMmap = true
    
    # Cache size for frequently accessed data
    cacheSize = "128MB"
}
EOF

# Create strfry database directory with proper ownership
mkdir -p /var/lib/strfry/db
chown -R strfry:strfry /var/lib/strfry

# Test strfry binary before creating service
echo "Testing strfry binary..."
if ! /usr/local/bin/strfry --help > /dev/null 2>&1; then
    echo "ERROR: strfry binary test failed"
    exit 1
fi

# Initialize the database as strfry user (only if not already initialized)
if [ "$RERUN" = "false" ] || [ ! -f "/var/lib/strfry/db/data.mdb" ]; then
    echo "Initializing strfry database..."
    sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=0 > /dev/null 2>&1 || true
else
    echo "Skipping database initialization (already exists)"
fi

# Create systemd service for strfry
if [ "$RERUN" = "false" ] || [ ! -f "/etc/systemd/system/strfry.service" ]; then
    echo "Creating strfry systemd service..."
    cat > /etc/systemd/system/strfry.service << 'EOF'
[Unit]
Description=strfry nostr discovery relay
After=network.target
Wants=network.target

[Service]
Type=simple
User=strfry
Group=strfry
ExecStart=/usr/local/bin/strfry --config=/etc/strfry/strfry.conf relay
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=strfry-discovery

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/strfry /var/log/strfry
ReadOnlyPaths=/etc/strfry

# Environment variables
Environment=STRFRY_DB=/var/lib/strfry/db

# File descriptor limits
LimitNOFILE=524288

[Install]
WantedBy=multi-user.target
EOF
else
    echo "Skipping strfry systemd service creation (already exists)"
fi

# Configure Caddy for discovery relay (always update the configuration)
echo "Configuring/updating Caddy for discovery relay..."
cat > /etc/caddy/Caddyfile << 'EOF'
# Global options
{
    # Enable admin API on localhost only
    admin localhost:2019
    
    # Disable automatic HTTPS for internal testing
    # auto_https off
    
    # Log settings
    log {
        output file /var/log/caddy/caddy.log
        level INFO
    }
}

# Main site configuration for discovery.eu.nostria.app
discovery.eu.nostria.app {
    # Enable automatic HTTPS
    tls {
        protocols tls1.2 tls1.3
    }
    
    # Security headers
    header {
        # Enable HSTS
        Strict-Transport-Security max-age=31536000;
        
        # Prevent clickjacking
        X-Frame-Options DENY
        
        # Prevent MIME sniffing
        X-Content-Type-Options nosniff
        
        # XSS protection
        X-XSS-Protection "1; mode=block"
        
        # Referrer policy
        Referrer-Policy strict-origin-when-cross-origin
        
        # Remove server information
        -Server
    }
    
    # WebSocket proxy for strfry nostr relay
    reverse_proxy localhost:7777 {
        # WebSocket support
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
    }
    
    # Access logging
    log {
        output file /var/log/caddy/discovery-access.log
        format json
    }
    
    # Error handling
    handle_errors {
        respond "Service temporarily unavailable" 503
    }
}

# Health check endpoint for monitoring
discovery.eu.nostria.app/health {
    respond "OK" 200
}

# Monitoring endpoint (internal access only via localhost)
localhost:8080 {
    # Strfry monitoring endpoint
    reverse_proxy /metrics localhost:7778
    
    # Basic health check
    handle /health {
        respond "Discovery Relay OK" 200
    }
    
    # System stats
    handle /stats {
        respond "Discovery relay statistics endpoint" 200
    }
}
EOF

# Always reload Caddy configuration after updating
if systemctl is-active --quiet caddy; then
    echo "Reloading Caddy configuration..."
    systemctl reload caddy || systemctl restart caddy
fi

# Enable and start services
echo "Enabling and starting services..."
systemctl daemon-reload
systemctl enable strfry
systemctl enable caddy

# Start strfry first, then Caddy
echo "Starting strfry service..."
systemctl start strfry
sleep 10

# Check if strfry started successfully
if ! systemctl is-active --quiet strfry; then
    echo "ERROR: strfry service failed to start"
    journalctl -u strfry --no-pager -n 20 || true
    exit 1
fi

echo "Starting caddy service..."
systemctl start caddy

# Configure system limits for strfry
echo "Configuring system limits..."
cat >> /etc/security/limits.conf << 'EOF'
# Increase file descriptor limits for strfry
strfry soft nofile 65536
strfry hard nofile 524288
* soft nofile 65536
* hard nofile 524288
EOF

# Configure systemd limits
mkdir -p /etc/systemd/system.conf.d/
cat > /etc/systemd/system.conf.d/limits.conf << 'EOF'
[Manager]
DefaultLimitNOFILE=524288
EOF

# Configure firewall (ufw)
echo "Configuring firewall..."
ufw --force enable
ufw allow ssh
ufw allow http
ufw allow https

# Setup log rotation for strfry
echo "Setting up log rotation..."
cat > /etc/logrotate.d/strfry << 'EOF'
/var/log/strfry/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 644 strfry strfry
    postrotate
        systemctl reload strfry
    endscript
}
EOF

# Create a discovery relay specific health check script
echo "Creating discovery relay health check script..."
cat > /usr/local/bin/strfry-discovery-health-check.sh << 'EOF'
#!/bin/bash
# Health check for discovery relay

# Check if strfry process is running
if ! pgrep -f "strfry.*relay" > /dev/null; then
    echo "ERROR: strfry process not running"
    exit 1
fi

# Check if strfry is listening on port 7777
if ! ss -ln | grep -q ":7777.*LISTEN"; then
    echo "ERROR: strfry not listening on port 7777"
    exit 1
fi

# Check if Caddy is running
if ! systemctl is-active --quiet caddy; then
    echo "ERROR: Caddy service not active"
    exit 1
fi

# Check if Caddy is listening on port 443
if ! ss -ln | grep -q ":443.*LISTEN"; then
    echo "ERROR: Caddy not listening on port 443"
    exit 1
fi

# Check strfry monitoring endpoint
if ! curl -s localhost:7778 > /dev/null; then
    echo "WARNING: strfry monitoring endpoint not responding"
fi

# Check database disk space
DB_USAGE=$(df /var/lib/strfry | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DB_USAGE" -gt 85 ]; then
    echo "WARNING: Database disk usage is ${DB_USAGE}% (threshold: 85%)"
    echo "Consider expanding the data disk in Azure Portal"
fi

# Check if database is on mounted disk
if ! mount | grep -q "/var/lib/strfry"; then
    echo "WARNING: Database directory not on mounted data disk"
fi

echo "OK: Discovery relay services are healthy"
echo "Database disk usage: ${DB_USAGE}%"
exit 0
EOF

chmod +x /usr/local/bin/strfry-discovery-health-check.sh

# Setup cron job for health monitoring
echo "Setting up health monitoring..."
cat > /etc/cron.d/strfry-discovery-health << 'EOF'
# Check discovery relay health every 5 minutes
*/5 * * * * root /usr/local/bin/strfry-discovery-health-check.sh >> /var/log/strfry-discovery-health.log 2>&1
EOF

# Clean up
echo "Cleaning up..."
cd /
rm -rf /tmp/strfry
apt-get autoremove -y
apt-get autoclean

echo "Discovery Relay VM setup completed successfully at $(date)"
echo "Services status:"
systemctl status strfry --no-pager -l || true
systemctl status caddy --no-pager -l || true

# Verify services are running
echo "Verifying services..."
sleep 10

echo "Running discovery relay health check..."
if /usr/local/bin/strfry-discovery-health-check.sh; then
    echo "SUCCESS: All discovery relay services are healthy"
else
    echo "WARNING: Some services may not be fully ready yet"
    echo "strfry logs:"
    journalctl -u strfry --no-pager -n 20 || true
    echo "caddy logs:"
    journalctl -u caddy --no-pager -n 20 || true
fi

echo "Setup completed! The discovery relay should be accessible at https://discovery.eu.nostria.app"
echo "You can check the relay info at: https://discovery.eu.nostria.app (WebSocket connection for nostr)"
echo "Internal monitoring available at: http://localhost:8080/health"
