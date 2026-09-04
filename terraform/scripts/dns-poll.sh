#!/bin/bash
# DNS Polling Script
# Site 5 - MSP Multi-Client Estate
#
# Verifies all required hostnames resolve to the exact expected Elastic IP.
# Runs every 5 minutes via systemd timer.
# Disables itself after successful HTTPS setup.

set -euo pipefail

EXPECTED_IP_FILE="/etc/expected_ip"
DOMAIN_NAME_FILE="/opt/paleon/domain_name.txt"
MAX_ATTEMPTS=30
ATTEMPT_FILE="/var/lib/paleon/dns-poll-attempt"
SUCCESS_FILE="/var/lib/paleon/dns-poll-success"

if [ ! -f "${EXPECTED_IP_FILE}" ]; then
  echo "ERROR: Expected IP file not found: ${EXPECTED_IP_FILE}"
  exit 1
fi

readarray -t EXPECTED_IPS < <(tr -d '[:space:]' < "${EXPECTED_IP_FILE}")
if [ "${#EXPECTED_IPS[@]}" -ne 2 ]; then
  echo "ERROR: Expected IP file must contain exactly two values: clean and clientc"
  exit 1
fi

EXPECTED_CLEAN_IP="${EXPECTED_IPS[0]}"
EXPECTED_CLIENTC_IP="${EXPECTED_IPS[1]}"

if [ ! -f "${DOMAIN_NAME_FILE}" ]; then
  echo "ERROR: Domain name file not found: ${DOMAIN_NAME_FILE}"
  exit 1
fi
DOMAIN_NAME=$(tr -d '[:space:]' < "${DOMAIN_NAME_FILE}")

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
FQDNS=()
for h in "${HOSTNAMES[@]}"; do
  FQDNS+=("${h}.${DOMAIN_NAME}")
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

if [ -f "${SUCCESS_FILE}" ]; then
  log "DNS verification already successful, exiting"
  exit 0
fi

mkdir -p "$(dirname "${ATTEMPT_FILE}")"
if [ -f "${ATTEMPT_FILE}" ]; then
  ATTEMPT=$(cat "${ATTEMPT_FILE}")
else
  ATTEMPT=0
fi
ATTEMPT=$((ATTEMPT + 1))
echo "${ATTEMPT}" > "${ATTEMPT_FILE}"

log "DNS Poll Attempt ${ATTEMPT}/${MAX_ATTEMPTS}"
log "Expected clean IP: ${EXPECTED_CLEAN_IP}"
log "Expected Client C IP: ${EXPECTED_CLIENTC_IP}"
log "Domain: ${DOMAIN_NAME}"

ALL_RESOLVED=true
FAILED_HOSTS=()

for fqdn in "${FQDNS[@]}"; do
  RESOLVED_IPS=$(dig +short "${fqdn}" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)

  if [ -z "${RESOLVED_IPS}" ]; then
    log "FAIL: ${fqdn} - No A record found"
    ALL_RESOLVED=false
    FAILED_HOSTS+=("${fqdn} (no record)")
    continue
  fi

  EXPECTED_IP="${EXPECTED_CLEAN_IP}"
  if [ "${fqdn}" = "clientc.${DOMAIN_NAME}" ]; then
    EXPECTED_IP="${EXPECTED_CLIENTC_IP}"
  fi

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

if [ "${ALL_RESOLVED}" = true ]; then
  log "SUCCESS: All hostnames resolve to expected exact IPs"
  touch "${SUCCESS_FILE}"
  log "Triggering certificate setup..."
  systemctl start paleon-cert-setup.service
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