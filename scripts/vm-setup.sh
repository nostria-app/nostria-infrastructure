#!/bin/bash
set -e

# Log all output to a file for debugging
exec > >(tee -a /var/log/vm-setup.log) 2>&1
echo "Starting VM setup at $(date)"

# Update system
echo "Updating system packages..."
export DEBIAN_FRONTEND=noninteractive

# Configure proper package sources
echo "Configuring package sources..."
cat > /etc/apt/sources.list << 'EOF'
deb http://archive.ubuntu.com/ubuntu jammy main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu jammy-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu jammy-security main restricted universe multiverse
EOF

apt-get update
apt-get upgrade -y

# Install required packages for strfry compilation
echo "Installing build dependencies..."
apt-get install -y build-essential git wget curl net-tools
apt-get install -y libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev

# Verify essential tools are available
if ! command -v make &> /dev/null; then
    echo "ERROR: make command not found after installation"
    exit 1
fi

if ! command -v g++ &> /dev/null; then
    echo "ERROR: g++ command not found after installation"
    exit 1
fi

# Install Caddy using alternative method to avoid GPG issues
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

# Create strfry user
echo "Creating strfry user..."
useradd -r -s /bin/false -d /var/lib/strfry strfry

# Create directories
echo "Creating directories..."
mkdir -p /var/lib/strfry
mkdir -p /etc/strfry
mkdir -p /var/log/strfry
chown strfry:strfry /var/lib/strfry /var/log/strfry

# Clone and compile strfry
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

# Create strfry configuration
echo "Creating strfry configuration..."
cat > /etc/strfry/strfry.conf << 'EOF'
##
## strfry relay config for Nostria VM deployment
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
        name = "Nostria VM Relay"

        # NIP-11: Detailed plain-text description of relay
        description = "A high-performance Nostria relay running on dedicated VM infrastructure with strfry and Caddy"

        # NIP-11: Administrative nostr pubkey, for contact purposes
        pubkey = "17e2889fba01021d048a13fd0ba108ad31c38326295460c21e69c43fa8fbe515"

        # NIP-11: Alternative contact
        contact = "mailto:admin@nostria.app"

        # NIP-11: List of supported NIPs
        supported_nips = [1, 2, 4, 9, 11, 15, 16, 20, 22, 28, 33, 40]

        # NIP-11: Software information
        software = "git+https://github.com/hoytech/strfry.git"
        version = "latest"

        # NIP-11: Relay limitations
        limitation {
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
}

# Enable built-in monitoring webserver
monitoring {
    bind = "127.0.0.1"
    port = 7778
}

# Event retention policy
retention = [
    {
        kinds = [0, 3]
        count = 1
    },
    {
        kinds = [1]
        time = 2592000
    },
    {
        kinds = [7]
        time = 604800
    },
    {
        time = 604800
    }
]
EOF

# Create strfry database directory
mkdir -p /var/lib/strfry/db
chown -R strfry:strfry /var/lib/strfry

# Test strfry binary before creating service
echo "Testing strfry binary..."
if ! /usr/local/bin/strfry --help > /dev/null 2>&1; then
    echo "ERROR: strfry binary test failed"
    exit 1
fi

# Initialize the database as strfry user
echo "Initializing strfry database..."
sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf export --limit=0 > /dev/null 2>&1 || true

# Create systemd service for strfry
echo "Creating strfry systemd service..."
cat > /etc/systemd/system/strfry.service << 'EOF'
[Unit]
Description=strfry nostr relay
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
SyslogIdentifier=strfry

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

# Configure Caddy
echo "Configuring Caddy..."
cat > /etc/caddy/Caddyfile << 'EOF'
# Global options
{
    email admin@nostria.app
    admin localhost:2019
}

# Main site configuration for test.ribo.eu.nostria.app
test.ribo.eu.nostria.app {
    # Reverse proxy to strfry
    reverse_proxy 127.0.0.1:7777

    # Security headers
    header {
        # Remove server information
        -Server
        # Security headers
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
        Referrer-Policy strict-origin-when-cross-origin
        # HSTS
        Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
    }

    # Logging
    log {
        output file /var/log/caddy/access.log
        format json
    }

    # NIP-11 relay information endpoint
    handle /.well-known/nostr.json {
        header Content-Type "application/json"
        respond `{
            "names": {},
            "relays": {
                "test.ribo.eu.nostria.app": ["wss://test.ribo.eu.nostria.app"]
            }
        }` 200
    }

    # Health check endpoint
    handle /health {
        header Content-Type "text/plain"
        respond "OK" 200
    }

    # Status endpoint
    handle /status {
        header Content-Type "application/json"
        respond `{
            "relay": "Nostria VM Relay",
            "version": "1.0.0",
            "description": "High-performance nostr relay on VM",
            "contact": "admin@nostria.app",
            "supported_nips": [1, 2, 4, 9, 11, 15, 16, 20, 22, 28, 33, 40]
        }` 200
    }
}

# Monitoring endpoint (internal only)
localhost:8080 {
    handle /metrics {
        metrics
    }
    
    handle /strfry/* {
        uri strip_prefix /strfry
        reverse_proxy 127.0.0.1:7778
    }
    
    handle /health {
        header Content-Type "application/json"
        respond `{"status": "healthy", "timestamp": "{time.now.unix}"}` 200
    }
}
EOF

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
    echo "ERROR: strfry failed to start, checking logs..."
    journalctl -u strfry --no-pager -l
    echo "Attempting to run strfry manually for debugging..."
    sudo -u strfry /usr/local/bin/strfry --config=/etc/strfry/strfry.conf relay &
    STRFRY_PID=$!
    sleep 5
    if kill -0 $STRFRY_PID 2>/dev/null; then
        echo "strfry started manually, killing and restarting service..."
        kill $STRFRY_PID
        systemctl restart strfry
        sleep 5
    fi
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
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 strfry strfry
    postrotate
        systemctl reload strfry > /dev/null 2>&1 || true
    endscript
}
EOF

# Create a simple health check script
echo "Creating health check script..."
cat > /usr/local/bin/strfry-health-check.sh << 'EOF'
#!/bin/bash
# Simple health check for strfry relay

# Check if strfry process is running
if ! pgrep -f "strfry.*relay" > /dev/null; then
    echo "ERROR: strfry process not found"
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

echo "OK: All services are healthy"
exit 0
EOF

chmod +x /usr/local/bin/strfry-health-check.sh

# Setup cron job for health monitoring
echo "Setting up health monitoring..."
cat > /etc/cron.d/strfry-health << 'EOF'
# Check strfry relay health every 5 minutes
*/5 * * * * root /usr/local/bin/strfry-health-check.sh >> /var/log/strfry-health.log 2>&1
EOF

# Clean up
echo "Cleaning up..."
cd /
rm -rf /tmp/strfry
apt-get autoremove -y
apt-get autoclean

echo "VM setup completed successfully at $(date)"
echo "Services status:"
systemctl status strfry --no-pager -l || true
systemctl status caddy --no-pager -l || true

# Verify services are running
echo "Verifying services..."
sleep 10

echo "Running health check..."
if /usr/local/bin/strfry-health-check.sh; then
    echo "SUCCESS: All services are healthy"
else
    echo "WARNING: Health check failed, showing logs for debugging..."
    echo "strfry logs:"
    journalctl -u strfry --no-pager -n 20 || true
    echo "caddy logs:"
    journalctl -u caddy --no-pager -n 20 || true
fi

echo "Setup completed! The relay should be accessible at https://test.ribo.eu.nostria.app"
