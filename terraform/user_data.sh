#!/bin/bash
# User Data Bootstrap Script
# Site 5 - MSP Multi-Client Estate
#
# This script runs on EC2 first boot and performs the complete deployment.
# It is completely self-contained and idempotent.
#
# NOTE: Bash $${VAR} references are escaped as $${VAR} for Terraform templatefile.
# Only the 4 template variables (repo_url, domain_name, expected_ip, aws_region)
# use Terraform interpolation syntax $${...}.

set -euo pipefail

# ============================================================================
# CONFIGURATION (passed via templatefile from Terraform)
# ============================================================================

REPO_URL="${repo_url}"
DOMAIN_NAME="${domain_name}"
EXPECTED_IP="${expected_ip}"
AWS_REGION="${aws_region}"

# Derived values
HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
FQDNS=()
for h in "$${HOSTNAMES[@]}"; do
  FQDNS+=("$${h}.$${DOMAIN_NAME}")
done

# Paths
WEBSITE_ROOT="/var/www"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/ssl/certs"
LETSENCRYPT_DIR="/etc/letsencrypt/live"
SCRIPTS_DIR="/opt/paleon/scripts"
EXPECTED_IP_FILE="/etc/expected_ip"
BOOTSTRAP_LOG="/var/log/paleon-bootstrap.log"
DNS_POLL_LOG="/var/log/paleon-dns-poll.log"
CERT_SETUP_LOG="/var/log/paleon-cert-setup.log"

# ============================================================================
# LOGGING SETUP
# ============================================================================

exec 1> >(tee -a "$${BOOTSTRAP_LOG}")
exec 2> >(tee -a "$${BOOTSTRAP_LOG}" >&2)

log() {
  echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $$*"
}

log "=== PALEON SITE 5 BOOTSTRAP STARTED ==="
log "Domain: $${DOMAIN_NAME}"
log "Expected IP: $${EXPECTED_IP}"
log "Repo: $${REPO_URL}"

# ============================================================================
# STEP 1: WRITE EXPECTED IP FILE
# ============================================================================

log "Step 1: Writing expected IP to $${EXPECTED_IP_FILE}"
echo "$${EXPECTED_IP}" > "$${EXPECTED_IP_FILE}"
chmod 644 "$${EXPECTED_IP_FILE}"

# ============================================================================
# STEP 2: INSTALL DEPENDENCIES
# ============================================================================

log "Step 2: Installing dependencies"
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  nginx \
  certbot \
  python3-certbot-nginx \
  socat \
  curl \
  jq \
  dnsutils \
  git \
  openssl \
  ca-certificates \
  logrotate

log "Dependencies installed"

# ============================================================================
# STEP 3: CLONE REPOSITORY
# ============================================================================

log "Step 3: Cloning repository from $${REPO_URL}"
cd /opt
if [ -d "paleon" ]; then
  log "Repository exists, pulling latest"
  cd paleon
  git pull origin main
else
  git clone "$${REPO_URL}" paleon
  cd paleon
fi

# Verify repo structure
if [ ! -d "website" ] || [ ! -d "nginx" ]; then
  log "ERROR: Repository missing required directories"
  exit 1
fi

log "Repository cloned successfully"

# ============================================================================
# STEP 4: DEPLOY WEBSITE CONTENT
# ============================================================================

log "Step 4: Deploying website content to $${WEBSITE_ROOT}"

# Create website directories
for host in "$${HOSTNAMES[@]}"; do
  mkdir -p "$${WEBSITE_ROOT}/$${host}"
done

# Copy website files
cp -r /opt/paleon/website/* "$${WEBSITE_ROOT}/"

# Ensure .git directory for clientc exists and has correct content
mkdir -p "$${WEBSITE_ROOT}/clientc/.git"
cp /opt/paleon/website/clientc/.git/HEAD "$${WEBSITE_ROOT}/clientc/.git/HEAD"
cp /opt/paleon/website/clientc/.git/config "$${WEBSITE_ROOT}/clientc/.git/config"

# Set permissions
chown -R www-data:www-data "$${WEBSITE_ROOT}"
find "$${WEBSITE_ROOT}" -type f -exec chmod 644 {} \;
find "$${WEBSITE_ROOT}" -type d -exec chmod 755 {} \;

log "Website content deployed"

# ============================================================================
# STEP 5: DEPLOY HTTP BOOTSTRAP NGINX CONFIGS
# ============================================================================

log "Step 5: Deploying HTTP bootstrap Nginx configs"

# Copy bootstrap configs
cp /opt/paleon/nginx/http-bootstrap/*.conf "$${NGINX_AVAILABLE}/"

# Enable sites
for host in "$${HOSTNAMES[@]}"; do
  ln -sf "$${NGINX_AVAILABLE}/$${host}.conf" "$${NGINX_ENABLED}/$${host}.conf"
done

# Remove default site
rm -f "$${NGINX_ENABLED}/default"

# Create ACME challenge directory
mkdir -p /var/www/letsencrypt
chown -R www-data:www-data /var/www/letsencrypt

# Test nginx config
nginx -t

# Start nginx
systemctl enable nginx
systemctl restart nginx

log "HTTP bootstrap Nginx deployed and started"

# ============================================================================
# STEP 6: DEPLOY SCRIPTS
# ============================================================================

log "Step 6: Deploying operational scripts"

mkdir -p "$${SCRIPTS_DIR}"

# Copy scripts
cp /opt/paleon/terraform/scripts/*.sh "$${SCRIPTS_DIR}/"
chmod +x "$${SCRIPTS_DIR}"/*.sh

# DNS Poll Script - replace placeholder with actual expected IP
sed -i "s|EXPECTED_IP_PLACEHOLDER|$${EXPECTED_IP}|g" "$${SCRIPTS_DIR}/dns-poll.sh"

# Cert setup script - replace placeholders
sed -i "s|DOMAIN_NAME_PLACEHOLDER|$${DOMAIN_NAME}|g" "$${SCRIPTS_DIR}/cert-setup.sh"
sed -i "s|EXPECTED_IP_PLACEHOLDER|$${EXPECTED_IP}|g" "$${SCRIPTS_DIR}/cert-setup.sh"

# Dummy listener script
# No replacements needed

log "Scripts deployed"

# ============================================================================
# STEP 7: INSTALL SYSTEMD UNITS
# ============================================================================

log "Step 7: Installing systemd units"

# DNS Poll Service
cat > /etc/systemd/system/paleon-dns-poll.service << 'EOF'
[Unit]
Description=Paleon DNS Polling Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/paleon/scripts/dns-poll.sh
StandardOutput=append:/var/log/paleon-dns-poll.log
StandardError=append:/var/log/paleon-dns-poll.log
User=root
EOF

# DNS Poll Timer (every 5 minutes)
cat > /etc/systemd/system/paleon-dns-poll.timer << 'EOF'
[Unit]
Description=Run DNS polling every 5 minutes
Requires=paleon-dns-poll.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Cert Setup Service (triggered by DNS poll success)
cat > /etc/systemd/system/paleon-cert-setup.service << 'EOF'
[Unit]
Description=Paleon Certificate Setup Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/paleon/scripts/cert-setup.sh
StandardOutput=append:/var/log/paleon-cert-setup.log
StandardError=append:/var/log/paleon-cert-setup.log
User=root
EOF

# Dummy Listener Service
cat > /etc/systemd/system/paleon-dummy-listener.service << 'EOF'
[Unit]
Description=Paleon Dummy PostgreSQL Listener (Client C Test)
After=network-online.target paleon-cert-setup.service
Wants=network-online.target

[Service]
Type=simple
User=www-data
ExecStart=/opt/paleon/scripts/dummy-listener.sh
Restart=on-failure
RestartSec=10
StandardOutput=append:/var/log/paleon-dummy-listener.log
StandardError=append:/var/log/paleon-dummy-listener.log

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable timers
systemctl enable paleon-dns-poll.timer
systemctl start paleon-dns-poll.timer

log "Systemd units installed and DNS polling started"

# ============================================================================
# STEP 8: GENERATE SELF-SIGNED CERTIFICATES (Client B & C)
# ============================================================================

log "Step 8: Generating self-signed certificates for Client B & C"

# Client B - Expiring in ~10 days
log "Generating Client B certificate (expiring in 10 days)"
openssl genrsa -out "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.key" 2048
openssl req -x509 -new -key "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.key" \
  -out "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.crt" \
  -days 10 \
  -subj "/CN=clientb.$${DOMAIN_NAME}" \
  -addext "subjectAltName=DNS:clientb.$${DOMAIN_NAME}"

# Client C - Expired
log "Generating Client C certificate (expired)"
openssl genrsa -out "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.key" 2048
# notBefore: 30 days ago, notAfter: 1 day ago (expired)
OPENSSL_STARTDATE=$$(date -d '30 days ago' +'%Y%m%d%H%M%S')Z
OPENSSL_ENDDATE=$$(date -d '1 day ago' +'%Y%m%d%H%M%S')Z
openssl req -x509 -new -key "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.key" \
  -out "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.crt" \
  -days -1 \
  -subj "/CN=clientc.$${DOMAIN_NAME}" \
  -addext "subjectAltName=DNS:clientc.$${DOMAIN_NAME}" \
  -startdate "$${OPENSSL_STARTDATE}" \
  -enddate "$${OPENSSL_ENDDATE}"

# Set permissions
chmod 640 "$${SSL_DIR}"/*.key
chmod 644 "$${SSL_DIR}"/*.crt
chown root:ssl-cert "$${SSL_DIR}"/*.key "$${SSL_DIR}"/*.crt 2>/dev/null || true

log "Self-signed certificates generated"

# Verify certificates
for domain in "clientb.$${DOMAIN_NAME}" "clientc.$${DOMAIN_NAME}"; do
  log "Certificate details for $${domain}:"
  openssl x509 -in "$${SSL_DIR}/$${domain}.crt" -noout -dates -subject -issuer
done

# ============================================================================
# BOOTSTRAP COMPLETE - DNS Polling will handle certificate setup
# ============================================================================

log "=== BOOTSTRAP COMPLETE ==="
log "HTTP server running on port 80"
log "DNS polling active (every 5 minutes)"
log "Self-signed certs for Client B & C generated"
log "Let's Encrypt certs will be provisioned after DNS verification"
log "Dummy listener will start after HTTPS setup"
log "Check logs: $${BOOTSTRAP_LOG}"