#!/bin/bash
set -e

# Log all output to a file for debugging
exec > >(tee -a /var/log/vm-setup.log) 2>&1
echo "Starting VM setup at $(date)"

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages for strfry compilation
echo "Installing build dependencies..."
apt-get install -y git g++ make libssl-dev zlib1g-dev liblmdb-dev libflatbuffers-dev libsecp256k1-dev libzstd-dev curl

# Install Caddy
echo "Installing Caddy..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

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
    nofiles = 1000000

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
ReadWritePaths=/var/lib/strfry
ReadOnlyPaths=/etc/strfry

[Install]
WantedBy=multi-user.target
EOF

# Configure Caddy
echo "Configuring Caddy..."
cat > /etc/caddy/Caddyfile << 'EOF'
# Global options
{
    auto_https on
    email admin@nostria.app
    admin localhost:2019
}

# Main site configuration for test.ribo.eu.nostria.app
test.ribo.eu.nostria.app {
    # Reverse proxy to strfry
    reverse_proxy 127.0.0.1:7777 {
        # WebSocket support
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

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
        respond `{
            "names": {},
            "relays": {
                "test.ribo.eu.nostria.app": ["wss://test.ribo.eu.nostria.app"]
            }
        }` 200 {
            Content-Type "application/json"
        }
    }

    # Health check endpoint
    handle /health {
        respond "OK" 200
    }

    # Status endpoint
    handle /status {
        respond `{
            "relay": "Nostria VM Relay",
            "version": "1.0.0",
            "description": "High-performance nostr relay on VM",
            "contact": "admin@nostria.app",
            "supported_nips": [1, 2, 4, 9, 11, 15, 16, 20, 22, 28, 33, 40]
        }` 200 {
            Content-Type "application/json"
        }
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
        respond `{"status": "healthy", "timestamp": "{time.now.unix}"}` 200 {
            Content-Type "application/json"
        }
    }
}
EOF

# Create log directory for Caddy
mkdir -p /var/log/caddy
chown caddy:caddy /var/log/caddy

# Enable and start services
echo "Enabling and starting services..."
systemctl daemon-reload
systemctl enable strfry
systemctl enable caddy

# Start strfry first, then Caddy
systemctl start strfry
sleep 5
systemctl start caddy

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
if ! netstat -ln | grep -q ":7777.*LISTEN"; then
    echo "ERROR: strfry not listening on port 7777"
    exit 1
fi

# Check if Caddy is running
if ! systemctl is-active --quiet caddy; then
    echo "ERROR: Caddy service not active"
    exit 1
fi

# Check if Caddy is listening on port 443
if ! netstat -ln | grep -q ":443.*LISTEN"; then
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
systemctl status strfry --no-pager -l
systemctl status caddy --no-pager -l

echo "Setup completed! The relay should be accessible at https://test.ribo.eu.nostria.app"
