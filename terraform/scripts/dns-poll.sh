#!/bin/bash
# DNS Polling Script
# Site 5 - MSP Multi-Client Estate
#
# Verifies all required hostnames resolve to the expected Elastic IP.
# Runs every 5 minutes via systemd timer.
# Disables itself after successful HTTPS setup.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

EXPECTED_IP_FILE="/etc/expected_ip"
DOMAIN_NAME_FILE="/opt/paleon/domain_name.txt"
MAX_ATTEMPTS=30  # 30 * 5 min = 150 min max
ATTEMPT_FILE="/var/lib/paleon/dns-poll-attempt"
SUCCESS_FILE="/var/lib/paleon/dns-poll-success"
SCRIPTS_DIR="/opt/paleon/scripts"

# Read expected IP
if [ ! -f "${EXPECTED_IP_FILE}" ]; then
  echo "ERROR: Expected IP file not found: ${EXPECTED_IP_FILE}"
  exit 1
fi

EXPECTED_IP=$(cat "${EXPECTED_IP_FILE}" | tr -d '[:space:]')

# Read domain name
if [ ! -f "${DOMAIN_NAME_FILE}" ]; then
  echo "ERROR: Domain name file not found: ${DOMAIN_NAME_FILE}"
  exit 1
fi

DOMAIN_NAME=$(cat "${DOMAIN_NAME_FILE}" | tr -d '[:space:]')

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
FQDNS=()
for h in "${HOSTNAMES[@]}"; do
  FQDNS+=("${h}.${DOMAIN_NAME}")
done

# ============================================================================
# LOGGING
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ============================================================================
# CHECK IF ALREADY SUCCESSFUL
# ============================================================================

if [ -f "${SUCCESS_FILE}" ]; then
  log "DNS verification already successful, exiting"
  exit 0
fi

# ============================================================================
# TRACK ATTEMPTS
# ============================================================================

mkdir -p "$(dirname "${ATTEMPT_FILE}")"

if [ -f "${ATTEMPT_FILE}" ]; then
  ATTEMPT=$(cat "${ATTEMPT_FILE}")
else
  ATTEMPT=0
fi

ATTEMPT=$((ATTEMPT + 1))
echo "${ATTEMPT}" > "${ATTEMPT_FILE}"

log "DNS Poll Attempt ${ATTEMPT}/${MAX_ATTEMPTS}"
log "Expected IP: ${EXPECTED_IP}"
log "Domain: ${DOMAIN_NAME}"

# ============================================================================
# VERIFY DNS RESOLUTION
# ============================================================================

ALL_RESOLVED=true
FAILED_HOSTS=()

for fqdn in "${FQDNS[@]}"; do
  # Query DNS
  RESOLVED_IPS=$(dig +short "${fqdn}" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)

  if [ -z "${RESOLVED_IPS}" ]; then
    log "FAIL: ${fqdn} - No A record found"
    ALL_RESOLVED=false
    FAILED_HOSTS+=("${fqdn} (no record)")
    continue
  fi

  # Check if ALL resolved IPs match expected IP
  # (Should only be one IP, but be thorough)
  MATCH=true
  for ip in ${RESOLVED_IPS}; do
    if [ "${ip}" != "${EXPECTED_IP}" ]; then
      MATCH=false
      break
    fi
  done

  if [ "${MATCH}" = true ]; then
    log "OK: ${fqdn} -> ${EXPECTED_IP}"
  else
    log "FAIL: ${fqdn} -> ${RESOLVED_IPS} (expected ${EXPECTED_IP})"
    ALL_RESOLVED=false
    FAILED_HOSTS+=("${fqdn} (wrong IP: ${RESOLVED_IPS})")
  fi
done

# ============================================================================
# HANDLE RESULTS
# ============================================================================

if [ "${ALL_RESOLVED}" = true ]; then
  log "SUCCESS: All hostnames resolve to expected IP ${EXPECTED_IP}"

  # Mark success
  touch "${SUCCESS_FILE}"

  # Trigger certificate setup
  log "Triggering certificate setup..."
  systemctl start paleon-cert-setup.service

  # Disable timer (no more polling needed)
  log "Disabling DNS polling timer"
  systemctl stop paleon-dns-poll.timer
  systemctl disable paleon-dns-poll.timer

  exit 0
else
  log "FAILURE: Some hostnames not resolved correctly"
  for failed in "${FAILED_HOSTS[@]}"; do
    log "  - ${failed}"
  done

  if [ "${ATTEMPT}" -ge "${MAX_ATTEMPTS}" ]; then
    log "MAX ATTEMPTS REACHED (${MAX_ATTEMPTS}). Stopping timer."
    systemctl stop paleon-dns-poll.timer
    systemctl disable paleon-dns-poll.timer
    log "DNS polling disabled. Manual intervention required."
    exit 1
  fi

  log "Retrying in 5 minutes (attempt ${ATTEMPT}/${MAX_ATTEMPTS})"
  exit 1
fi