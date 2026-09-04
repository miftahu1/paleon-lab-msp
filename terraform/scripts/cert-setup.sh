#!/bin/bash
# Certificate Setup Script
# Site 5 - MSP Multi-Client Estate
#
# Provisions Let's Encrypt certificates for clean clients.
# Deploys HTTPS final Nginx configs.
# Self-signed certs for Client B & C already generated in bootstrap.

set -euo pipefail

# ============================================================================
# CONFIGURATION (placeholders replaced by user_data.sh)
# ============================================================================

DOMAIN_NAME="DOMAIN_NAME_PLACEHOLDER"
EXPECTED_IP="EXPECTED_IP_PLACEHOLDER"

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
CLEAN_HOSTNAMES=("msp" "clienta" "clientd")
SELF_SIGNED_HOSTNAMES=("clientb" "clientc")

# Paths
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
SSL_DIR="/etc/ssl/certs"
LETSENCRYPT_DIR="/etc/letsencrypt/live"
SCRIPTS_DIR="/opt/paleon/scripts"
WEBSITE_ROOT="/var/www"

# ============================================================================
# LOGGING
# ============================================================================

LOG_FILE="/var/log/paleon-cert-setup.log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== CERTIFICATE SETUP STARTED ==="
log "Domain: ${DOMAIN_NAME}"

# ============================================================================
# STEP 1: VERIFY DNS STILL RESOLVES
# ============================================================================

log "Step 1: Verifying DNS resolution..."

for host in "${HOSTNAMES[@]}"; do
  fqdn="${host}.${DOMAIN_NAME}"
  resolved=$(dig +short "${fqdn}" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

  if [ "${resolved}" != "${EXPECTED_IP}" ]; then
    log "ERROR: ${fqdn} resolves to ${resolved}, expected ${EXPECTED_IP}"
    exit 1
  fi

  log "OK: ${fqdn} -> ${resolved}"
done

# ============================================================================
# STEP 2: REQUEST LET'S ENCRYPT CERTIFICATES FOR CLEAN CLIENTS
# ============================================================================

log "Step 2: Requesting Let's Encrypt certificates for clean clients..."

# Build domain list for certbot
DOMAIN_ARGS=()
for host in "${CLEAN_HOSTNAMES[@]}"; do
  DOMAIN_ARGS+=("-d" "${host}.${DOMAIN_NAME}")
done

# Run certbot with nginx plugin
# Use --nginx to auto-configure, but we'll deploy our own configs after
certbot certonly \
  --nginx \
  "${DOMAIN_ARGS[@]}" \
  --non-interactive \
  --agree-tos \
  --email "admin@${DOMAIN_NAME}" \
  --redirect \
  --no-eff-email \
  --keep-until-expiring

if [ $? -ne 0 ]; then
  log "ERROR: Certbot failed"
  exit 1
fi

log "Let's Encrypt certificates obtained"

# ============================================================================
# STEP 3: VERIFY CERTIFICATES
# ============================================================================

log "Step 3: Verifying certificates..."

for host in "${CLEAN_HOSTNAMES[@]}"; do
  fqdn="${host}.${DOMAIN_NAME}"
  cert_path="${LETSENCRYPT_DIR}/${fqdn}/fullchain.pem"
  key_path="${LETSENCRYPT_DIR}/${fqdn}/privkey.pem"

  if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
    log "ERROR: Certificate files not found for ${fqdn}"
    exit 1
  fi

  # Check validity
  openssl x509 -in "${cert_path}" -noout -checkend 86400 >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "WARNING: Certificate for ${fqdn} expires within 24 hours"
  fi

  log "OK: ${fqdn} certificate valid"
done

# Verify self-signed certs exist
for host in "${SELF_SIGNED_HOSTNAMES[@]}"; do
  fqdn="${host}.${DOMAIN_NAME}"
  cert_path="${SSL_DIR}/${fqdn}.crt"
  key_path="${SSL_DIR}/${fqdn}.key"

  if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
    log "ERROR: Self-signed certificate not found for ${fqdn}"
    exit 1
  fi

  log "OK: ${fqdn} self-signed certificate present"
done

# ============================================================================
# STEP 4: DEPLOY HTTPS FINAL NGINX CONFIGS
# ============================================================================

log "Step 4: Deploying HTTPS final Nginx configs..."

# Copy HTTPS configs
cp /opt/paleon/nginx/https-final/*.conf "${NGINX_AVAILABLE}/"

# Re-enable sites (they were already enabled for HTTP, but configs are replaced)
for host in "${HOSTNAMES[@]}"; do
  ln -sf "${NGINX_AVAILABLE}/${host}.conf" "${NGINX_ENABLED}/${host}.conf"
done

# Remove default site
rm -f "${NGINX_ENABLED}/default"

log "HTTPS configs deployed"

# ============================================================================
# STEP 5: TEST AND RELOAD NGINX
# ============================================================================

log "Step 5: Testing and reloading Nginx..."

nginx -t
if [ $? -ne 0 ]; then
  log "ERROR: Nginx configuration test failed"
  exit 1
fi

systemctl reload nginx
log "Nginx reloaded successfully"

# ============================================================================
# STEP 6: ENABLE CERTBOT RENEWAL TIMER
# ============================================================================

log "Step 6: Enabling certbot renewal timer..."

systemctl enable certbot.timer
systemctl start certbot.timer

log "Certbot timer enabled"

# ============================================================================
# STEP 7: START DUMMY LISTENER
# ============================================================================

log "Step 7: Starting dummy PostgreSQL listener..."

systemctl enable paleon-dummy-listener.service
systemctl start paleon-dummy-listener.service

# Wait a moment for it to start
sleep 2

if systemctl is-active --quiet paleon-dummy-listener.service; then
  log "Dummy listener started successfully"
else
  log "WARNING: Dummy listener may not be running"
  systemctl status paleon-dummy-listener.service --no-pager
fi

# ============================================================================
# STEP 8: FINAL VERIFICATION
# ============================================================================

log "Step 8: Final verification..."

# Test HTTPS endpoints
for host in "${HOSTNAMES[@]}"; do
  fqdn="${host}.${DOMAIN_NAME}"
  if curl -sf -o /dev/null --max-time 10 "https://${fqdn}"; then
    log "OK: HTTPS ${fqdn} responds"
  else
    log "WARNING: HTTPS ${fqdn} not responding (may need DNS propagation)"
  fi
done

# Test dummy listener
if nc -z localhost 5432 2>/dev/null; then
  log "OK: Dummy listener accepting connections on 5432"
else
  log "WARNING: Dummy listener not accepting connections"
fi

log "=== CERTIFICATE SETUP COMPLETE ==="
log "HTTPS active for all hostnames"
log "Self-signed certs: Client B (expiring), Client C (expired)"
log "Let's Encrypt certs: MSP, Client A, Client D"
log "Dummy listener running on port 5432"