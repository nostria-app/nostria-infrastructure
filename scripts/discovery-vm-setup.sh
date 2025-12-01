#!/bin/bash
set -e

# Enhanced error handling function
error_exit() {
    echo "ERROR: $1" >&2
    echo "Script failed at line $2" >&2
    echo "Command: $3" >&2
    exit "${4:-1}"
}

# Trap errors and provide context
trap 'error_exit "Script failed" $LINENO "$BASH_COMMAND" $?' ERR

# Get force update parameter if provided
FORCE_UPDATE=${1:-"initial"}

# Log all output to a file for debugging
exec > >(tee -a /var/log/discovery-vm-setup.log) 2>&1
echo "Starting Discovery Relay VM setup at $(date) with force update: $FORCE_UPDATE"
echo "Running on: $(hostname) ($(uname -a))"
echo "Available memory: $(free -h)"
echo "Available disk space: $(df -h)"
echo "Network interfaces: $(ip addr show | grep -E '^[0-9]+:' | cut -d: -f2)"

# Test basic system requirements
echo "Testing basic system requirements..."
if ! command -v apt-get &> /dev/null; then
    error_exit "apt-get not found - this script requires Ubuntu/Debian" $LINENO "$BASH_COMMAND" 8
fi

if ! command -v systemctl &> /dev/null; then
    error_exit "systemctl not found - this script requires systemd" $LINENO "$BASH_COMMAND" 8
fi

# Test internet connectivity early
echo "Testing internet connectivity..."
if ! ping -c 3 8.8.8.8 > /dev/null 2>&1; then
    echo "WARNING: Cannot ping 8.8.8.8 - checking DNS resolution..."
    if ! nslookup google.com > /dev/null 2>&1; then
        error_exit "No internet connectivity detected" $LINENO "$BASH_COMMAND" 8
    fi
    echo "DNS resolution works, continuing..."
fi
echo "Internet connectivity confirmed"

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

    echo "Updating package lists..."
    if ! apt-get update; then
        echo "WARNING: apt-get update failed on first attempt, retrying in 10 seconds..."
        sleep 10
        if ! apt-get update; then
            error_exit "Failed to update package lists after retry" $LINENO "$BASH_COMMAND" 8
        fi
    fi
    
    echo "Upgrading system packages..."
    if ! apt-get upgrade -y; then
        echo "WARNING: System upgrade failed, continuing anyway..."
    fi

    # Setup data disk for strfry database
    echo "Setting up data disk for strfry database..."
    
    # List all available disks for debugging
    echo "Available disks:"
    lsblk -dn -o NAME,SIZE,TYPE,MOUNTPOINT
    
    # Find the data disk (should be the first unpartitioned disk that's not the OS disk)
    # Look for a disk that doesn't have any partitions and isn't the root disk
    ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
    ROOT_DISK=$(echo "$ROOT_DEVICE" | sed 's/[0-9]*$//' | sed 's|/dev/||')
    echo "Root device: $ROOT_DEVICE, Root disk identified as: $ROOT_DISK"
    
    # Find data disk by looking for disks that are not the root disk
    # Prefer larger disks and avoid the OS disk and temp disk
    echo "Looking for data disk (excluding root disk: $ROOT_DISK)..."
    
    # Get all disks except the root disk, sorted by size (largest first)
    AVAILABLE_DISKS=$(lsblk -dn -o NAME,SIZE,TYPE | grep "disk" | grep -v "$ROOT_DISK" | sort -k2 -hr)
    echo "Available non-root disks (sorted by size):"
    echo "$AVAILABLE_DISKS"
    
    # Select the largest available disk as data disk (should be the 64GB disk)
    DATA_DISK=$(echo "$AVAILABLE_DISKS" | head -n1 | awk '{print $1}')
    
    if [ -n "$DATA_DISK" ]; then
        DATA_DISK_SIZE=$(echo "$AVAILABLE_DISKS" | head -n1 | awk '{print $2}')
        echo "Selected data disk: /dev/$DATA_DISK (size: $DATA_DISK_SIZE)"
    else
        echo "No suitable data disk found"
    fi
    
    if [ -n "$DATA_DISK" ]; then
        echo "Found data disk: /dev/$DATA_DISK"
        
        # Safety check: ensure we're not about to mount the root disk
        if [ "$DATA_DISK" = "$ROOT_DISK" ]; then
            echo "ERROR: Selected data disk is the same as root disk. Aborting to prevent data loss."
            exit 1
        fi
        
        # Always create the mount point directory first
        mkdir -p /var/lib/strfry
        
        # Verify the mount point is empty or only contains expected directories
        if [ "$(ls -A /var/lib/strfry 2>/dev/null | wc -l)" -gt 0 ]; then
            echo "Mount point /var/lib/strfry is not empty. Contents:"
            ls -la /var/lib/strfry/
            # If it contains system directories like 'bin', 'etc', etc., something is wrong
            if ls /var/lib/strfry/ | grep -E '^(bin|etc|usr|var|root|home)$' > /dev/null; then
                echo "ERROR: Mount point contains system directories. This suggests a previous mount error."
                echo "Cleaning up and recreating mount point..."
                umount /var/lib/strfry 2>/dev/null || true
                rm -rf /var/lib/strfry
                mkdir -p /var/lib/strfry
            fi
        fi
        
        # Check if the disk already has partitions
        if [ $(lsblk -n /dev/$DATA_DISK | wc -l) -gt 1 ]; then
            echo "Data disk already has partitions, checking if mounted..."
            PARTITION="${DATA_DISK}1"
            if mount | grep -q "/dev/$PARTITION.*on /var/lib/strfry"; then
                echo "Data disk partition already mounted at /var/lib/strfry"
            elif mount | grep -q "/dev/$PARTITION"; then
                echo "Data disk partition mounted elsewhere, remounting to /var/lib/strfry..."
                # Unmount from current location
                umount /dev/$PARTITION 2>/dev/null || true
                # Mount to correct location
                mount /dev/$PARTITION /var/lib/strfry || {
                    echo "Failed to mount existing partition, will reformat..."
                    # Format and mount
                    mkfs.ext4 -F /dev/$PARTITION
                    mount /dev/$PARTITION /var/lib/strfry
                }
            else
                echo "Mounting existing data disk partition to /var/lib/strfry..."
                mount /dev/$PARTITION /var/lib/strfry || {
                    echo "Failed to mount existing partition, will reformat..."
                    # Format and mount
                    mkfs.ext4 -F /dev/$PARTITION
                    mount /dev/$PARTITION /var/lib/strfry
                }
            fi
        else
            echo "Creating new partition on data disk..."
            # Create partition table and partition
            parted /dev/$DATA_DISK --script mklabel gpt
            parted /dev/$DATA_DISK --script mkpart primary ext4 0% 100%
            
            # Wait a moment for partition to be recognized
            sleep 2
            
            # Format the partition with ext4
            mkfs.ext4 -F /dev/${DATA_DISK}1
            
            # Mount the disk
            mount /dev/${DATA_DISK}1 /var/lib/strfry
        fi
        
        # Get UUID for permanent mounting
        DATA_UUID=$(blkid -s UUID -o value /dev/${DATA_DISK}1)
        echo "Data disk UUID: $DATA_UUID"
        
        # Add to fstab for permanent mounting (remove any existing entry first)
        sed -i '\|/var/lib/strfry|d' /etc/fstab
        echo "UUID=$DATA_UUID /var/lib/strfry ext4 defaults,noatime 0 2" >> /etc/fstab
        
        # Note: Ownership will be set later after the strfry user is created
        echo "Data disk setup complete (ownership will be set after user creation)"
        
        echo "Data disk mounted successfully at /var/lib/strfry"
        df -h /var/lib/strfry
    else
        echo "No additional data disk found, using OS disk for database"
        mkdir -p /var/lib/strfry
    fi
else
    echo "Skipping package sources configuration (rerun detected)"
    echo "Updating package lists for rerun..."
    if ! apt-get update; then
        echo "WARNING: apt-get update failed on rerun, retrying..."
        sleep 5
        apt-get update || echo "WARNING: Package update still failed on rerun"
    fi
fi

# Install required packages for strfry compilation
if [ "$RERUN" = "false" ]; then
    echo "Installing build dependencies..."
    echo "Installing basic build tools..."
    if ! apt-get install -y build-essential git wget curl net-tools; then
        error_exit "Failed to install basic build tools" $LINENO "$BASH_COMMAND" 8
    fi
    
    echo "Installing development libraries..."
    if ! apt-get install -y libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev; then
        error_exit "Failed to install development libraries" $LINENO "$BASH_COMMAND" 8
    fi
    
    echo "Installing additional tools for Caddy..."
    if ! apt-get install -y libnss3-tools; then
        echo "WARNING: Failed to install libnss3-tools (certificate management will have warnings)"
    fi

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
    
    # Test network connectivity first
    echo "Testing network connectivity..."
    if ! curl -s --connect-timeout 10 https://api.github.com/repos/caddyserver/caddy/releases/latest > /dev/null; then
        echo "ERROR: Cannot reach GitHub. Network connectivity issue detected."
        echo "Waiting 30 seconds for network to stabilize..."
        sleep 30
        if ! curl -s --connect-timeout 10 https://api.github.com/repos/caddyserver/caddy/releases/latest > /dev/null; then
            echo "ERROR: Still cannot reach GitHub. Aborting Caddy installation."
            exit 8
        fi
    fi
    echo "Network connectivity confirmed"
    
    # Create temporary directory for download
    CADDY_TEMP_DIR=$(mktemp -d)
    echo "Using temporary directory: $CADDY_TEMP_DIR"
    
    # Download with more verbose output and error checking
    CADDY_URL="https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz"
    echo "Downloading from: $CADDY_URL"
    
    if ! wget --timeout=60 --tries=3 --progress=dot:binary "$CADDY_URL" -O "$CADDY_TEMP_DIR/caddy.tar.gz"; then
        echo "ERROR: Failed to download Caddy from GitHub"
        echo "Trying alternative download method with curl..."
        if ! curl -L --connect-timeout 60 --max-time 300 "$CADDY_URL" -o "$CADDY_TEMP_DIR/caddy.tar.gz"; then
            echo "ERROR: Both wget and curl failed to download Caddy"
            echo "Attempting fallback installation using apt package manager..."
            rm -rf "$CADDY_TEMP_DIR"
            
            # Fallback: Try to install Caddy from official repository
            echo "Adding Caddy official repository..."
            apt-get update
            apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
            
            if curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null; then
                curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
                apt-get update
                if apt-get install -y caddy; then
                    echo "Caddy installed successfully via apt package manager"
                    # Skip the manual installation steps below
                    CADDY_INSTALLED_VIA_APT=true
                else
                    error_exit "Failed to install Caddy via apt as well" $LINENO "$BASH_COMMAND" 8
                fi
            else
                error_exit "All Caddy installation methods failed" $LINENO "$BASH_COMMAND" 8
            fi
        fi
    fi
    
    # Only proceed with manual installation if not installed via apt
    if [ "${CADDY_INSTALLED_VIA_APT:-false}" != "true" ]; then
    
    echo "Download completed successfully"
    
    # Verify download
    if [ ! -f "$CADDY_TEMP_DIR/caddy.tar.gz" ] || [ ! -s "$CADDY_TEMP_DIR/caddy.tar.gz" ]; then
        echo "ERROR: Downloaded file is missing or empty"
        ls -la "$CADDY_TEMP_DIR/"
        rm -rf "$CADDY_TEMP_DIR"
        exit 8
    fi
    
    echo "Extracting Caddy archive..."
    cd "$CADDY_TEMP_DIR"
    
    if ! tar -xzf caddy.tar.gz; then
        echo "ERROR: Failed to extract Caddy archive"
        ls -la "$CADDY_TEMP_DIR/"
        file caddy.tar.gz
        rm -rf "$CADDY_TEMP_DIR"
        exit 8
    fi
    
    # Verify extraction
    if [ ! -f "caddy" ]; then
        echo "ERROR: Caddy binary not found after extraction"
        ls -la "$CADDY_TEMP_DIR/"
        rm -rf "$CADDY_TEMP_DIR"
        exit 8
    fi
    
    echo "Installing Caddy binary..."
    if ! mv caddy /usr/local/bin/; then
        echo "ERROR: Failed to move Caddy binary to /usr/local/bin/"
        ls -la /usr/local/bin/
        rm -rf "$CADDY_TEMP_DIR"
        exit 8
    fi
    
    chmod +x /usr/local/bin/caddy
    
    # Verify installation
    if ! /usr/local/bin/caddy version; then
        echo "ERROR: Caddy binary is not working properly"
        ls -la /usr/local/bin/caddy
        rm -rf "$CADDY_TEMP_DIR"
        exit 8
    fi
    
    # Clean up
    rm -rf "$CADDY_TEMP_DIR"
    echo "Caddy installation completed successfully"
    fi  # End of manual installation block

    # Create caddy user and group (for both installation methods)
    if ! getent group caddy > /dev/null; then
        groupadd --system caddy
    fi
    if ! getent passwd caddy > /dev/null; then
        useradd --system --gid caddy --create-home --home-dir /var/lib/caddy --shell /usr/sbin/nologin --comment "Caddy web server" caddy
    fi

    # Create necessary directories
    mkdir -p /etc/caddy
    mkdir -p /var/log/caddy
    mkdir -p /var/lib/caddy/certificates
    chown -R caddy:caddy /var/lib/caddy
    chown -R caddy:caddy /var/log/caddy
    
    # Ensure proper permissions for certificate storage
    chmod 700 /var/lib/caddy/certificates

else
    echo "Skipping Caddy installation (already exists or rerun detected)"
fi

# Determine Caddy binary path (for both installation methods)
CADDY_BINARY_PATH="/usr/local/bin/caddy"
if [ "${CADDY_INSTALLED_VIA_APT:-false}" = "true" ] || [ -f "/usr/bin/caddy" ]; then
    CADDY_BINARY_PATH="/usr/bin/caddy"
fi

echo "Using Caddy binary at: $CADDY_BINARY_PATH"

# Set capability for Caddy to bind to privileged ports
echo "Setting CAP_NET_BIND_SERVICE capability on Caddy binary..."
if ! setcap 'cap_net_bind_service=+ep' "$CADDY_BINARY_PATH"; then
    echo "WARNING: Failed to set capabilities on Caddy binary. Port binding may require root privileges."
else
    echo "✓ Caddy binary capabilities set successfully"
    # Verify the capability
    echo "Verifying capability: $(getcap "$CADDY_BINARY_PATH" || echo 'getcap failed')"
fi

# Create systemd service for Caddy (after binary path is determined)
echo "Creating Caddy systemd service..."
cat > /etc/systemd/system/caddy.service << EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=$CADDY_BINARY_PATH run --environ --config /etc/caddy/Caddyfile
ExecReload=$CADDY_BINARY_PATH reload --config /etc/caddy/Caddyfile --force
TimeoutStartSec=60s
TimeoutStopSec=5s
TimeoutReloadSec=30s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# Create strfry user
if [ "$RERUN" = "false" ]; then
    echo "Creating strfry user..."
    useradd -r -s /bin/false -d /var/lib/strfry strfry

    # Create directories (after data disk is mounted)
    echo "Creating directories..."
    mkdir -p /var/lib/strfry/db
    mkdir -p /etc/strfry
    mkdir -p /var/log/strfry
    
    # Set proper ownership and permissions on all strfry directories (including mounted data disk)
    echo "Setting ownership and permissions on strfry directories..."
    chown -R strfry:strfry /var/lib/strfry /var/log/strfry
    chmod -R 755 /var/lib/strfry
    chmod -R 755 /var/log/strfry
else
    echo "Skipping strfry user creation (rerun detected)"
    # Ensure directories exist and have proper ownership
    mkdir -p /var/lib/strfry/db
    mkdir -p /etc/strfry
    mkdir -p /var/log/strfry
    
    # Set proper ownership recursively on the entire strfry directory tree
    # This is critical for mounted data disks
    echo "Setting proper ownership on strfry directories..."
    chown -R strfry:strfry /var/lib/strfry /var/log/strfry
    chmod -R 755 /var/lib/strfry
    chmod -R 755 /var/log/strfry
    
    # Ensure database directory has correct permissions
    chmod 755 /var/lib/strfry/db
    chown strfry:strfry /var/lib/strfry/db
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
        pubkey = "d1bd33333733dcc411f0ee893b38b8522fc0de227fff459d99044ced9e65581b"

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
        posting_policy = "https://www.nostria.app/policy"

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
echo "Ensuring proper ownership on strfry database directory..."
mkdir -p /var/lib/strfry/db
chown -R strfry:strfry /var/lib/strfry
chmod -R 755 /var/lib/strfry

# Verify ownership is correct
echo "Verifying strfry directory ownership:"
ls -la /var/lib/strfry/
ls -la /var/lib/strfry/db/ 2>/dev/null || echo "Database directory will be created on first run"

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

# Determine the region more reliably
# Try to get region from VM name pattern (nostria-{region}-discovery-vm)
REGION=$(hostname | sed -n 's/.*nostria-\([a-z][a-z]\)-discovery.*/\1/p')

# If that fails, try to get from Azure metadata or resource group
if [ -z "$REGION" ]; then
    # Try from Azure metadata (if available)
    REGION=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01" 2>/dev/null | sed -n 's/.*nostria-\([a-z][a-z]\)-.*/\1/p' || echo "")
fi

# Default to 'eu' if still can't determine
if [ -z "$REGION" ]; then
    REGION="eu"
    echo "Warning: Could not determine region from hostname '$(hostname)', defaulting to 'eu'"
fi

DISCOVERY_DOMAIN="discovery.${REGION}.nostria.app"
echo "Configuring Caddy for domain: $DISCOVERY_DOMAIN (region: $REGION, hostname: $(hostname))"

cat > /etc/caddy/Caddyfile << EOF
# Global options
{
	# Enable admin API on localhost only
	admin localhost:2019
	
	# Disable automatic HTTPS for initial deployment to prevent hanging
	auto_https off
	
	# Set storage location for certificates (writable by caddy user)
	storage file_system {
		root /var/lib/caddy/certificates
	}
	
	# Log settings
	log {
		output file /var/log/caddy/caddy.log
		level INFO
	}
}

# Main site configuration for $DISCOVERY_DOMAIN (HTTP for initial deployment)
$DISCOVERY_DOMAIN:80 {
	# Security headers (no HSTS for HTTP)
	header {
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
	
	# Health check endpoint (moved inside main site)
	handle /health {
		respond "OK" 200
	}
	
	# WebSocket proxy for strfry nostr relay (catch-all for other paths)
	handle {
		reverse_proxy localhost:7777 {
			# WebSocket support
			header_up Host {host}
			header_up X-Real-IP {remote_host}
			header_up X-Forwarded-For {remote_host}
			header_up X-Forwarded-Proto {scheme}
			header_up X-Forwarded-Host {host}
		}
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

# Monitoring endpoint (internal access only via localhost)
localhost:8080 {
	# Strfry monitoring endpoint
	handle /metrics {
		reverse_proxy localhost:7778
	}
	
	# Basic health check
	handle /health {
		respond "Discovery Relay OK" 200
	}
	
	# System stats
	handle /stats {
		respond "Discovery relay statistics endpoint" 200
	}
	
	# Default response
	handle {
		respond "Internal monitoring interface" 200
	}
}
EOF

# Format the Caddyfile to fix formatting warnings
echo "Formatting Caddyfile..."
if command -v "$CADDY_BINARY_PATH" &> /dev/null; then
    $CADDY_BINARY_PATH fmt --overwrite /etc/caddy/Caddyfile || echo "WARNING: Failed to format Caddyfile"
fi

# Validate the Caddyfile
echo "Validating Caddyfile..."
if command -v "$CADDY_BINARY_PATH" &> /dev/null; then
    if ! $CADDY_BINARY_PATH validate --config /etc/caddy/Caddyfile; then
        echo "ERROR: Caddyfile validation failed"
        cat /etc/caddy/Caddyfile
        exit 1
    fi
    echo "Caddyfile validation passed"
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
# Stop any existing Caddy process first to avoid conflicts
systemctl stop caddy 2>/dev/null || true
sleep 2

# Start Caddy with timeout protection
timeout 60 systemctl start caddy &
CADDY_START_PID=$!

# Wait for Caddy to start with timeout
echo "Waiting for Caddy to start (timeout: 60 seconds)..."
CADDY_STARTED=false
for i in {1..60}; do
    if systemctl is-active --quiet caddy; then
        CADDY_STARTED=true
        echo "Caddy started successfully after $i seconds"
        break
    fi
    sleep 1
done

# Kill the start command if it's still running
kill $CADDY_START_PID 2>/dev/null || true

if [ "$CADDY_STARTED" = "false" ]; then
    echo "ERROR: Caddy failed to start within 60 seconds"
    echo "Caddy service status:"
    systemctl status caddy --no-pager -l || true
    echo "Recent Caddy logs:"
    journalctl -u caddy --no-pager -n 20 || true
    echo "Caddyfile contents:"
    cat /etc/caddy/Caddyfile
    exit 1
fi

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
DB_USAGE=$(df /var/lib/strfry 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
if [ "$DB_USAGE" -gt 85 ]; then
    echo "WARNING: Database disk usage is ${DB_USAGE}% (threshold: 85%)"
    echo "Consider expanding the data disk in Azure Portal"
fi

# Check if database is on mounted disk (more robust check)
STRFRY_MOUNT=$(df /var/lib/strfry 2>/dev/null | tail -1 | awk '{print $1}')
ROOT_MOUNT=$(df / 2>/dev/null | tail -1 | awk '{print $1}')

if [ "$STRFRY_MOUNT" != "$ROOT_MOUNT" ]; then
    echo "INFO: Database is on separate data disk: $STRFRY_MOUNT"
else
    echo "WARNING: Database directory appears to be on root filesystem"
    echo "Expected: separate data disk, Actual: $STRFRY_MOUNT"
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

echo "Setup completed! The discovery relay is accessible at http://$DISCOVERY_DOMAIN"
echo "You can check the relay info at: http://$DISCOVERY_DOMAIN (WebSocket connection for nostr)"
echo "Internal monitoring available at: http://localhost:8080/health"

echo ""
echo "=== IMPORTANT: Enable HTTPS after DNS configuration ==="
echo "This deployment uses HTTP to avoid certificate acquisition timeouts."
echo "After you configure DNS records for $DISCOVERY_DOMAIN pointing to this VM's public IP:"
echo ""
echo "1. Update DNS: Point $DISCOVERY_DOMAIN to $(curl -s ifconfig.me 2>/dev/null || echo 'VM-PUBLIC-IP')"
echo "2. Wait for DNS propagation (5-30 minutes)"
echo "3. Enable HTTPS by running:"
echo "   curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/enable-https.sh | sudo bash"
echo ""
echo "Or manually on the VM:"
echo "   sudo /path/to/enable-https.sh"
echo ""

# Optional: Setup strfry router for syncing with other relays
echo "=== Optional: Strfry Router Setup ==="
echo "To enable syncing event kinds 3 and 10002 with other relays, run:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/setup-strfry-router.sh | sudo bash"
echo ""
echo "This will configure:"
echo "  - Two-way sync with other Nostria Discovery Relays (multi-region)"
echo "  - Two-way sync with purplepag.es (kinds 3, 10002)"
echo "  - One-way sync from relay.damus.io and relay.primal.net (kinds 3, 10002)"
echo ""
echo "⚠️  IMPORTANT: For historical events, also run initial full sync:"
echo "  curl -s https://raw.githubusercontent.com/nostria-app/nostria-infrastructure/main/scripts/strfry-initial-full-sync.sh | sudo bash"
echo ""
echo "The router only syncs NEW events by default."
echo "The initial sync downloads existing contact lists and relay lists from all configured relays."
echo "  - One-way sync from relay.damus.io and relay.primal.net (kinds 3, 10002)"
