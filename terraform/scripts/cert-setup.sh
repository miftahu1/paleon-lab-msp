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
EXPECTED_CLEAN_IP="EXPECTED_CLEAN_IP_PLACEHOLDER"
EXPECTED_CLIENTC_IP="EXPECTED_CLIENTC_IP_PLACEHOLDER"
INSTANCE_ROLE="INSTANCE_ROLE_PLACEHOLDER"

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
# Clean instance: only request Let's Encrypt for msp, clienta, clientd
CLEAN_HOSTNAMES=("msp" "clienta" "clientd")
# Self-signed certs live for clientb and clientc (clientc is expired)
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
log "Instance role: ${INSTANCE_ROLE}"

# ============================================================================
# STEP 1: VERIFY DNS STILL RESOLVES
# ============================================================================

log "Step 1: Verifying DNS resolution..."

if [ "${INSTANCE_ROLE}" = "clean" ]; then
  for host in "${CLEAN_HOSTNAMES[@]}"; do
    fqdn="${host}.${DOMAIN_NAME}"
    resolved=$(dig +short "${fqdn}" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

    if [ "${resolved}" != "${EXPECTED_CLEAN_IP}" ]; then
      log "ERROR: ${fqdn} resolves to ${resolved}, expected ${EXPECTED_CLEAN_IP}"
      exit 1
    fi

    log "OK: ${fqdn} -> ${resolved}"
  done
elif [ "${INSTANCE_ROLE}" = "clientc" ]; then
  fqdn="clientc.${DOMAIN_NAME}"
  resolved=$(dig +short "${fqdn}" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

  if [ "${resolved}" != "${EXPECTED_CLIENTC_IP}" ]; then
    log "ERROR: ${fqdn} resolves to ${resolved}, expected ${EXPECTED_CLIENTC_IP}"
    exit 1
  fi

  log "OK: ${fqdn} -> ${resolved}"
else
  log "ERROR: Unsupported instance role: ${INSTANCE_ROLE}"
  exit 1
fi

# ============================================================================
# STEP 2: REQUEST LET'S ENCRYPT CERTIFICATES FOR CLEAN CLIENTS
# ============================================================================

if [ "${INSTANCE_ROLE}" = "clean" ]; then
  log "Step 2: Requesting Let's Encrypt certificates for clean clients..."

  # Use webroot mode and request certificates per-host to ensure
  # /etc/letsencrypt/live/<fqdn>/ directories are created individually
  LETSENCRYPT_WEBROOT="${WEBSITE_ROOT}/letsencrypt"
  mkdir -p "${LETSENCRYPT_WEBROOT}"

  for host in "${CLEAN_HOSTNAMES[@]}"; do
    fqdn="${host}.${DOMAIN_NAME}"
    log "Requesting Let's Encrypt cert for ${fqdn}"

    if ! certbot certonly \
      --webroot -w "${LETSENCRYPT_WEBROOT}" \
      -d "${fqdn}" \
      --non-interactive \
      --agree-tos \
      --email "admin@${DOMAIN_NAME}" \
      --no-eff-email \
      --keep-until-expiring; then
      log "ERROR: Certbot failed for ${fqdn}"
      exit 1
    fi

    log "Let's Encrypt certificate obtained for ${fqdn}"
  done
else
  log "Step 2: Client C instance does not request Let's Encrypt certificates."
fi

# ============================================================================
# STEP 3: VERIFY CERTIFICATES
# ============================================================================

log "Step 3: Verifying certificates..."

if [ "${INSTANCE_ROLE}" = "clean" ]; then
  for host in "${CLEAN_HOSTNAMES[@]}"; do
    fqdn="${host}.${DOMAIN_NAME}"
    cert_path="${LETSENCRYPT_DIR}/${fqdn}/fullchain.pem"
    key_path="${LETSENCRYPT_DIR}/${fqdn}/privkey.pem"

    if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
      log "ERROR: Certificate files not found for ${fqdn}"
      exit 1
    fi

    if ! openssl x509 -in "${cert_path}" -noout -checkend 86400 >/dev/null 2>&1; then
      log "WARNING: Certificate for ${fqdn} expires within 24 hours"
    fi

    log "OK: ${fqdn} certificate valid"
  done

  for host in "clientb"; do
    fqdn="${host}.${DOMAIN_NAME}"
    cert_path="${SSL_DIR}/${fqdn}.crt"
    key_path="${SSL_DIR}/${fqdn}.key"

    if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
      log "ERROR: Self-signed certificate not found for ${fqdn}"
      exit 1
    fi

    log "OK: ${fqdn} self-signed certificate present"
  done
else
  fqdn="clientc.${DOMAIN_NAME}"
  cert_path="${SSL_DIR}/${fqdn}.crt"
  key_path="${SSL_DIR}/${fqdn}.key"

  if [ ! -f "${cert_path}" ] || [ ! -f "${key_path}" ]; then
    log "ERROR: Client C self-signed certificate not found for ${fqdn}"
    exit 1
  fi

  if openssl x509 -in "${cert_path}" -noout -checkend 0 >/dev/null 2>&1; then
    log "ERROR: Client C certificate unexpectedly still valid"
    exit 1
  else
    log "OK: ${fqdn} expired certificate present and expired"
  fi
fi

# ============================================================================
# STEP 4: DEPLOY HTTPS FINAL NGINX CONFIGS
# ============================================================================

log "Step 4: Deploying HTTPS final Nginx configs..."

cp /opt/paleon/nginx/https-final/*.conf "${NGINX_AVAILABLE}/"

if [ "${INSTANCE_ROLE}" = "clean" ]; then
  for host in "${CLEAN_HOSTNAMES[@]}"; do
    ln -sf "${NGINX_AVAILABLE}/${host}.conf" "${NGINX_ENABLED}/${host}.conf"
  done
  for host in clientc; do
    rm -f "${NGINX_ENABLED}/${host}.conf"
  done
else
  ln -sf "${NGINX_AVAILABLE}/clientc.conf" "${NGINX_ENABLED}/clientc.conf"
  for host in msp clienta clientb clientd; do
    rm -f "${NGINX_ENABLED}/${host}.conf"
  done
fi


# Ensure default is removed
rm -f "${NGINX_ENABLED}/default"

log "HTTPS configs deployed"

# ============================================================================
# STEP 5: TEST AND RELOAD NGINX
# ============================================================================

log "Step 5: Testing and reloading Nginx..."

if ! nginx -t; then
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
# STEP 7: START DUMMY LISTENER (CLIENT C ONLY)
# ==========================================================================

if [ "${INSTANCE_ROLE}" = "clientc" ]; then
  log "Step 7: Starting dummy PostgreSQL listener on Client C..."

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
else
  log "Step 7: Skipping dummy PostgreSQL listener on clean instance."
fi

# ============================================================================
# STEP 8: FINAL VERIFICATION
# ============================================================================

log "Step 8: Final verification..."

# Test HTTPS endpoints - role specific
if [ "${INSTANCE_ROLE}" = "clean" ]; then
  for host in "${CLEAN_HOSTNAMES[@]}" "clientb"; do
    fqdn="${host}.${DOMAIN_NAME}"
    if curl -sf -o /dev/null --max-time 10 "https://${fqdn}"; then
      log "OK: HTTPS ${fqdn} responds"
    else
      log "WARNING: HTTPS ${fqdn} not responding (may need DNS propagation)"
    fi
  done
else
  fqdn="clientc.${DOMAIN_NAME}"
  if curl -sf -o /dev/null --max-time 10 "https://${fqdn}"; then
    log "OK: HTTPS ${fqdn} responds"
  else
    log "WARNING: HTTPS ${fqdn} not responding (may need DNS propagation)"
  fi
fi

# Test dummy listener - role specific
if [ "${INSTANCE_ROLE}" = "clientc" ]; then
  if nc -z localhost 5432 2>/dev/null; then
    log "OK: Dummy listener accepting connections on 5432"
  else
    log "WARNING: Dummy listener may not be running on Client C"
    systemctl status paleon-dummy-listener.service --no-pager || true
  fi
else
  # On clean instances, the dummy listener must NOT be present; this is expected
  if nc -z localhost 5432 2>/dev/null; then
    log "FAIL: Unexpected dummy listener found on clean instance"
  else
    log "OK: No dummy listener on clean instance (expected)"
  fi
fi

log "=== CERTIFICATE SETUP COMPLETE ==="
if [ "${INSTANCE_ROLE}" = "clean" ]; then
  log "HTTPS active for: ${CLEAN_HOSTNAMES[*]} and Client B (self-signed)"
  log "Self-signed certs: Client B (expiring)"
  log "Let's Encrypt certs: ${CLEAN_HOSTNAMES[*]}"
  log "Dummy listener not enabled on clean instance"
elif [ "${INSTANCE_ROLE}" = "clientc" ]; then
  log "HTTPS active only for: clientc (self-signed expired)"
  log "Self-signed certs: Client C (expired)"
  log "Dummy listener active on port 5432"
else
  log "HTTPS/Certificate setup complete for role: ${INSTANCE_ROLE}"
fi