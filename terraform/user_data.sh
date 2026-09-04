#!/bin/bash
# User Data Bootstrap Script
# Site 5 - MSP Multi-Client Estate
#
# This script runs on EC2 first boot and performs the complete deployment.
# It is completely self-contained and idempotent.
#
# NOTE: Bash $${VAR} references are escaped as $${VAR} for Terraform templatefile.
# Only the 5 template variables (repo_url, domain_name, expected_clean_ip,
# expected_clientc_ip, aws_region) use Terraform interpolation syntax $${...}.

set -euo pipefail

# ============================================================================
# CONFIGURATION (passed via templatefile from Terraform)
# ============================================================================

REPO_URL="${repo_url}"
DOMAIN_NAME="${domain_name}"
EXPECTED_CLEAN_IP="${expected_clean_ip}"
EXPECTED_CLIENTC_IP="${expected_clientc_ip}"
AWS_REGION="${aws_region}"

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
FQDNS=()
for h in "$${HOSTNAMES[@]}"; do
  FQDNS+=("$${h}.$${DOMAIN_NAME}")
done

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

exec 1> >(tee -a "$${BOOTSTRAP_LOG}")
exec 2> >(tee -a "$${BOOTSTRAP_LOG}" >&2)

log() {
  echo "[$$(date '+%Y-%m-%d %H:%M:%S')] $$*"
}

log "=== PALEON SITE 5 BOOTSTRAP STARTED ==="
log "Domain: $${DOMAIN_NAME}"
log "Expected clean IP: $${EXPECTED_CLEAN_IP}"
log "Expected Client C IP: $${EXPECTED_CLIENTC_IP}"
log "Repo: $${REPO_URL}"

# Step 1
log "Step 1: Writing expected IP data to $${EXPECTED_IP_FILE}"
printf '%s\n%s\n' "$${EXPECTED_CLEAN_IP}" "$${EXPECTED_CLIENTC_IP}" > "$${EXPECTED_IP_FILE}"
chmod 644 "$${EXPECTED_IP_FILE}"

# Step 2 dependencies
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

# Step 3 clone repo
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

if [ ! -d "website" ] || [ ! -d "nginx" ]; then
  log "ERROR: Repository missing required directories"
  exit 1
fi

log "Repository cloned successfully"

# Step 4 deploy website content
log "Step 4: Deploying website content to $${WEBSITE_ROOT}"
for host in "$${HOSTNAMES[@]}"; do
  mkdir -p "$${WEBSITE_ROOT}/$${host}"
done
cp -r /opt/paleon/website/* "$${WEBSITE_ROOT}/"
mkdir -p "$${WEBSITE_ROOT}/clientc/.git"
cp /opt/paleon/website/clientc/.git/HEAD "$${WEBSITE_ROOT}/clientc/.git/HEAD"
cp /opt/paleon/website/clientc/.git/config "$${WEBSITE_ROOT}/clientc/.git/config"
chown -R www-data:www-data "$${WEBSITE_ROOT}"
find "$${WEBSITE_ROOT}" -type f -exec chmod 644 {} \;
find "$${WEBSITE_ROOT}" -type d -exec chmod 755 {} \;
log "Website content deployed"

# Step 5 deploy bootstrap nginx configs
log "Step 5: Deploying HTTP bootstrap Nginx configs"
cp /opt/paleon/nginx/http-bootstrap/*.conf "$${NGINX_AVAILABLE}/"
for host in "$${HOSTNAMES[@]}"; do
  ln -sf "$${NGINX_AVAILABLE}/$${host}.conf" "$${NGINX_ENABLED}/$${host}.conf"
done
rm -f "$${NGINX_ENABLED}/default"
mkdir -p /var/www/letsencrypt
chown -R www-data:www-data /var/www/letsencrypt
nginx -t
systemctl enable nginx
systemctl restart nginx
log "HTTP bootstrap Nginx deployed and started"

# Step 6 deploy scripts
log "Step 6: Deploying operational scripts"
mkdir -p "$${SCRIPTS_DIR}"
cp /opt/paleon/terraform/scripts/*.sh "$${SCRIPTS_DIR}/"
chmod +x "$${SCRIPTS_DIR}"/*.sh
sed -i "s|EXPECTED_CLEAN_IP_PLACEHOLDER|$${EXPECTED_CLEAN_IP}|g" "$${SCRIPTS_DIR}/dns-poll.sh"
sed -i "s|EXPECTED_CLIENTC_IP_PLACEHOLDER|$${EXPECTED_CLIENTC_IP}|g" "$${SCRIPTS_DIR}/dns-poll.sh"
sed -i "s|DOMAIN_NAME_PLACEHOLDER|$${DOMAIN_NAME}|g" "$${SCRIPTS_DIR}/cert-setup.sh"
sed -i "s|EXPECTED_CLEAN_IP_PLACEHOLDER|$${EXPECTED_CLEAN_IP}|g" "$${SCRIPTS_DIR}/cert-setup.sh"
sed -i "s|EXPECTED_CLIENTC_IP_PLACEHOLDER|$${EXPECTED_CLIENTC_IP}|g" "$${SCRIPTS_DIR}/cert-setup.sh"
log "Scripts deployed"

# Step 7 systemd units
log "Step 7: Installing systemd units"
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

systemctl daemon-reload
systemctl enable paleon-dns-poll.timer
systemctl start paleon-dns-poll.timer
log "Systemd units installed and DNS polling started"

# Step 8 cert generation for B and C.
log "Step 8: Generating client certificates"
mkdir -p "$${SSL_DIR}"

# Client B certificate: self-signed, valid for ~10 days from deployment
log "Generating Client B certificate"
openssl genrsa -out "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.key" 2048 >/dev/null 2>&1
openssl req -x509 -new -key "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.key" \
  -out "$${SSL_DIR}/clientb.$${DOMAIN_NAME}.crt" \
  -days 10 \
  -subj "/CN=clientb.$${DOMAIN_NAME}" \
  -addext "subjectAltName=DNS:clientb.$${DOMAIN_NAME}" >/dev/null 2>&1

# Client C certificate: deterministic expired cert using parent CA + specific start/end dates
log "Generating Client C certificate"
openssl genrsa -out "$${SSL_DIR}/clientc-ca.key" 2048 >/dev/null 2>&1
openssl req -x509 -new -key "$${SSL_DIR}/clientc-ca.key" \
  -sha256 -days 3650 \
  -subj "/CN=Paleon Client C Test Root" \
  -out "$${SSL_DIR}/clientc-ca.crt" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1
openssl genrsa -out "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.key" 2048 >/dev/null 2>&1
openssl req -new -key "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.key" \
  -subj "/CN=clientc.$${DOMAIN_NAME}" \
  -addext "subjectAltName=DNS:clientc.$${DOMAIN_NAME}" \
  -out "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.csr" >/dev/null 2>&1
cat > "$${SSL_DIR}/clientc-ca.cnf" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
private_key = $${SSL_DIR}/clientc-ca.key
certificate = $${SSL_DIR}/clientc-ca.crt
database = $${SSL_DIR}/clientc-ca.index
new_certs_dir = $${SSL_DIR}
serial = $${SSL_DIR}/clientc-ca.serial
default_md = sha256
policy = policy_any
x509_extensions = v3_server

[ policy_any ]
commonName = supplied

[ v3_server ]
subjectAltName = DNS:clientc.$${DOMAIN_NAME}
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF
: > "$${SSL_DIR}/clientc-ca.index"
printf '1000\n' > "$${SSL_DIR}/clientc-ca.serial"
START_DATE=$(date -u -d '30 days ago' +'%Y%m%d%H%M%SZ')
END_DATE=$(date -u -d '1 day ago' +'%Y%m%d%H%M%SZ')
openssl ca -batch -config "$${SSL_DIR}/clientc-ca.cnf" \
  -in "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.csr" \
  -out "$${SSL_DIR}/clientc.$${DOMAIN_NAME}.crt" \
  -startdate "$${START_DATE}" \
  -enddate "$${END_DATE}" >/dev/null 2>&1
chmod 640 "$${SSL_DIR}"/*.key
chmod 644 "$${SSL_DIR}"/*.crt
chown root:ssl-cert "$${SSL_DIR}"/*.key "$${SSL_DIR}"/*.crt 2>/dev/null || true

for domain in "clientb.$${DOMAIN_NAME}" "clientc.$${DOMAIN_NAME}"; do
  log "Certificate details for $${domain}:"
  openssl x509 -in "$${SSL_DIR}/$${domain}.crt" -noout -dates -subject -issuer
done

log "=== BOOTSTRAP COMPLETE ==="
log "HTTP server running on port 80"
log "DNS polling active (every 5 minutes)"
log "Self-signed certs for Client B & C generated"
log "Let's Encrypt certs will be provisioned after DNS verification"
log "Dummy listener will start after HTTPS setup"
log "Check logs: $${BOOTSTRAP_LOG}"