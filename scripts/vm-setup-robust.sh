#!/bin/bash
set -e

# Enhanced logging and error handling
exec > >(tee -a /var/log/vm-setup.log) 2>&1
echo "=== Starting Robust VM Setup at $(date) ==="

# Function for error handling
handle_error() {
    echo "ERROR: $1" >&2
    echo "ERROR occurred at line $2" >&2
    echo "Setup failed at $(date)" >&2
    exit 1
}

# Set up error trap
trap 'handle_error "Unexpected error" $LINENO' ERR

# Get force update parameter
FORCE_UPDATE=${1:-"initial"}
echo "Force update parameter: $FORCE_UPDATE"

# Check if this is a re-run
RERUN=false
if systemctl list-units --full -all | grep -Fq "strfry.service"; then
    echo "Detected existing strfry service - this is a configuration update"
    RERUN=true
fi

# Function to retry commands
retry_command() {
    local max_attempts=3
    local delay=5
    local command="$1"
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "Attempt $attempt/$max_attempts: $command"
        if eval "$command"; then
            echo "Command succeeded on attempt $attempt"
            return 0
        else
            echo "Command failed on attempt $attempt"
            if [ $attempt -lt $max_attempts ]; then
                echo "Waiting $delay seconds before retry..."
                sleep $delay
            fi
        fi
        ((attempt++))
    done
    
    echo "Command failed after $max_attempts attempts: $command"
    return 1
}

# Update system with retries
if [ "$RERUN" = "false" ]; then
    echo "=== Updating system packages ==="
    export DEBIAN_FRONTEND=noninteractive
    
    # Configure package sources with timeout handling
    echo "Configuring package sources..."
    cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF

    # Update with retries
    retry_command "timeout 300 apt-get update"
    retry_command "timeout 600 apt-get upgrade -y"
    
    echo "=== Setting up data disk ==="
    
    # Improved disk detection
    echo "Available block devices:"
    lsblk
    
    # Find root disk
    ROOT_DISK=$(lsblk -no NAME,MOUNTPOINT | grep -E "/$" | awk '{print $1}' | sed 's/[0-9]*$//')
    echo "Root disk: $ROOT_DISK"
    
    # Find data disk (exclude root disk and any mounted disks)
    DATA_DISK=""
    for disk in $(lsblk -dno NAME | grep -v "$ROOT_DISK"); do
        if ! lsblk "/dev/$disk" | grep -q "/"; then
            DATA_DISK="$disk"
            echo "Found potential data disk: $DATA_DISK"
            break
        fi
    done
    
    if [ -n "$DATA_DISK" ] && [ "$DATA_DISK" != "$ROOT_DISK" ]; then
        echo "Setting up data disk: /dev/$DATA_DISK"
        
        # Create strfry user first (needed for ownership)
        if ! id "strfry" &>/dev/null; then
            groupadd --system strfry
            useradd --system --gid strfry --create-home --home-dir /var/lib/strfry --shell /usr/sbin/nologin strfry
        fi
        
        # Create mount point
        mkdir -p /var/lib/strfry
        
        # Check if disk has partitions
        if ! lsblk "/dev/$DATA_DISK" | grep -q "${DATA_DISK}1"; then
            echo "Creating partition on data disk..."
            parted "/dev/$DATA_DISK" --script mklabel gpt
            parted "/dev/$DATA_DISK" --script mkpart primary ext4 0% 100%
            sleep 3  # Wait for partition recognition
        fi
        
        PARTITION="/dev/${DATA_DISK}1"
        
        # Check if partition needs formatting
        if ! blkid "$PARTITION" | grep -q "ext4"; then
            echo "Formatting partition with ext4..."
            mkfs.ext4 -F "$PARTITION"
        fi
        
        # Mount if not already mounted
        if ! mount | grep -q "$PARTITION"; then
            echo "Mounting data disk..."
            mount "$PARTITION" /var/lib/strfry
        fi
        
        # Add to fstab
        DATA_UUID=$(blkid -s UUID -o value "$PARTITION")
        if [ -n "$DATA_UUID" ]; then
            sed -i '\|/var/lib/strfry|d' /etc/fstab
            echo "UUID=$DATA_UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab
        fi
        
        # Set ownership
        chown -R strfry:strfry /var/lib/strfry
        chmod 755 /var/lib/strfry
        
        echo "Data disk setup complete"
        df -h /var/lib/strfry
    else
        echo "No suitable data disk found, using OS disk"
        mkdir -p /var/lib/strfry
        if ! id "strfry" &>/dev/null; then
            groupadd --system strfry
            useradd --system --gid strfry --create-home --home-dir /var/lib/strfry --shell /usr/sbin/nologin strfry
        fi
        chown -R strfry:strfry /var/lib/strfry
    fi
    
    echo "=== Installing build dependencies ==="
    retry_command "timeout 600 apt-get install -y build-essential git wget curl net-tools"
    retry_command "timeout 600 apt-get install -y libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev"
    
    # Verify tools
    for tool in make g++ git wget curl; do
        if ! command -v "$tool" &>/dev/null; then
            handle_error "$tool not found after installation" $LINENO
        fi
    done
    
    echo "=== Installing Caddy ==="
    if [ ! -f "/usr/local/bin/caddy" ]; then
        CADDY_VERSION="2.7.6"
        CADDY_URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
        
        echo "Downloading Caddy from: $CADDY_URL"
        retry_command "timeout 120 wget -q '$CADDY_URL' -O /tmp/caddy.tar.gz"
        
        cd /tmp
        tar -xzf caddy.tar.gz
        mv caddy /usr/local/bin/
        chmod +x /usr/local/bin/caddy
        rm -f caddy.tar.gz LICENSE README.md
        
        # Create caddy user
        if ! id "caddy" &>/dev/null; then
            groupadd --system caddy
            useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin caddy
        fi
        
        # Create directories
        mkdir -p /etc/caddy /var/lib/caddy /var/log/caddy
        chown caddy:caddy /var/lib/caddy /var/log/caddy
        
        echo "Caddy installed successfully"
    fi
    
else
    echo "Skipping initial setup (rerun detected)"
    apt-get update || true
fi

echo "=== Installing/Building strfry ==="

# Check if strfry is already built
if [ ! -f "/usr/local/bin/strfry" ] || [ "$RERUN" = "true" ]; then
    echo "Building strfry from source..."
    
    cd /tmp
    if [ -d "strfry" ]; then
        rm -rf strfry
    fi
    
    retry_command "timeout 300 git clone https://github.com/hoytech/strfry.git"
    cd strfry
    
    # Build with timeout
    echo "Configuring build..."
    timeout 300 git submodule update --init
    
    echo "Building strfry (this may take several minutes)..."
    timeout 1200 make setup-golpe
    timeout 1800 make -j$(nproc)
    
    # Install binary
    cp strfry /usr/local/bin/
    chmod +x /usr/local/bin/strfry
    
    echo "strfry built and installed successfully"
fi

echo "=== Configuring strfry ==="

# Create strfry config
cat > /etc/strfry.conf << 'EOF'
##
## Default strfry config
##

# Directory that contains the strfry LMDB database (restart required)
db = "/var/lib/strfry/strfry-db/"

dbParams {
    # Maximum number of threads/processes that can simultaneously have LMDB transactions open (restart required)
    maxreaders = 256

    # Size of mmap() to use when loading LMDB (restart required)
    mapsize = "1TB"
}

relay {
    # Interface to listen on. Use 0.0.0.0 to listen on all interfaces (restart required)
    bind = "127.0.0.1"

    # Port to open for the nostr websocket protocol (restart required)
    port = 7777

    # Set OS-limit on maximum number of open files/sockets (if 0, don't attempt to set) (restart required)
    nofiles = 1000000

    # HTTP header that contains the client's real IP, before reverse proxying (NGINX: X-Real-IP) (restart required)
    realIpHeader = "X-Forwarded-For"

    info {
        # NIP-11: Name of this server. Short/descriptive (< 30 characters)
        name = "strfry default"

        # NIP-11: Detailed information about this server, free-form
        description = "This is a strfry instance."

        # NIP-11: Administrative pubkey, for contact purposes
        pubkey = ""

        # NIP-11: Alternative administrative contact (email, website, etc)
        contact = ""
    }

    # Maximum accepted incoming message length (restart required)
    maxMessageLength = 131072

    # Maximum number of subscriptions per connection (restart required)
    maxSubsPerConnection = 20

    # Maximum total length of all active subscriptions' filters (restart required)
    maxFiltersPerSub = 100

    # Whether to reject events whose timestamp is too far in the past/future (restart required)
    rejectEventsNewerThanSeconds = 900
    rejectEventsOlderThanSeconds = 94608000

    # Whether to require events to be signed (if false, then signatures are verified but acceptance is not required) (restart required)
    requireSigned = true

    writePolicy {
        # If non-empty, path to an executable script that implements the writePolicy plugin logic
        plugin = ""
    }

    compression {
        # Use permessage-deflate compression if supported by client. Reduces bandwidth, but uses more CPU (restart required)
        enabled = true

        # Maintain a sliding window buffer for each connection. Improves compression ratio, but uses more memory (restart required)
        slidingWindow = true
    }

    logging {
        # Dump all incoming messages
        dumpInAll = false

        # Dump all incoming EVENT messages
        dumpInEvents = false

        # Dump all incoming REQ/CLOSE messages
        dumpInReqs = false

        # Log performance metrics for initial REQ database scans
        dbScanPerf = false

        # Log reason for invalid event rejection? Can be disabled to silence excessive logging
        invalidEvents = false
    }

    numThreads {
        # Ingester threads: route incoming requests, validate events/sigs (restart required)
        ingester = 3

        # reqWorker threads: Handle initial DB scan for events (restart required)
        reqWorker = 3

        # negentropy threads: Handle negentropy-specific DB scans (restart required)
        negentropy = 2

        # monitor threads: Handle periodic tasks (restart required)
        monitor = 3

        # yesstr threads: Handle yesstr protocol (restart required)
        yesstr = 1
    }
}
EOF

echo "=== Setting up systemd services ==="

# Create strfry systemd service
cat > /etc/systemd/system/strfry.service << 'EOF'
[Unit]
Description=strfry nostr relay
After=network.target

[Service]
Type=simple
User=strfry
Group=strfry
WorkingDirectory=/var/lib/strfry
ExecStart=/usr/local/bin/strfry relay
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/strfry
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Create basic Caddyfile for HTTP (HTTPS will be configured later)
cat > /etc/caddy/Caddyfile << 'EOF'
{
    admin off
    auto_https off
}

:80 {
    reverse_proxy 127.0.0.1:7777
    
    header {
        Access-Control-Allow-Origin *
        Access-Control-Allow-Methods "GET, POST, OPTIONS"
        Access-Control-Allow-Headers "Content-Type, Accept, Accept-Encoding, Sec-WebSocket-Protocol, Sec-WebSocket-Extensions, Sec-WebSocket-Key, Sec-WebSocket-Version, Upgrade, Connection"
    }
    
    # Handle WebSocket upgrade
    @websocket {
        header Connection upgrade
        header Upgrade websocket
    }
    reverse_proxy @websocket 127.0.0.1:7777
}
EOF

# Create Caddy systemd service
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

echo "=== Starting services ==="

# Ensure strfry database directory exists
mkdir -p /var/lib/strfry/strfry-db
chown -R strfry:strfry /var/lib/strfry

# Reload systemd and start services
systemctl daemon-reload

# Enable and start strfry
systemctl enable strfry
systemctl start strfry

# Enable and start caddy
systemctl enable caddy
systemctl start caddy

# Wait a moment and check status
sleep 5

echo "=== Service Status ==="
systemctl is-active strfry || handle_error "strfry service failed to start" $LINENO
systemctl is-active caddy || handle_error "caddy service failed to start" $LINENO

echo "strfry status:"
systemctl status strfry --no-pager -l

echo "caddy status:"
systemctl status caddy --no-pager -l

echo "=== Creating health check script ==="
cat > /usr/local/bin/strfry-health-check.sh << 'EOF'
#!/bin/bash

echo "=== Strfry Health Check ==="
echo "Date: $(date)"
echo

echo "Service Status:"
systemctl is-active strfry && echo "✓ strfry service is running" || echo "✗ strfry service is not running"
systemctl is-active caddy && echo "✓ caddy service is running" || echo "✗ caddy service is not running"
echo

echo "Port Status:"
netstat -tlnp | grep :7777 && echo "✓ strfry listening on port 7777" || echo "✗ strfry not listening on port 7777"
netstat -tlnp | grep :80 && echo "✓ caddy listening on port 80" || echo "✗ caddy not listening on port 80"
echo

echo "Disk Usage:"
df -h /var/lib/strfry
echo

echo "Recent strfry logs:"
journalctl -u strfry --no-pager -l -n 10
echo

echo "Recent caddy logs:"
journalctl -u caddy --no-pager -l -n 10
EOF

chmod +x /usr/local/bin/strfry-health-check.sh

echo "=== Setup Complete ==="
echo "Strfry relay is running on port 7777"
echo "Caddy reverse proxy is running on port 80"
echo "Use '/usr/local/bin/strfry-health-check.sh' to check status"
echo "Setup completed successfully at $(date)"
