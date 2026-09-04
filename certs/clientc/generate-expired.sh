#!/bin/bash
# generate-expired.sh - Generate self-signed certificate that is ALREADY EXPIRED
# For Client C (Neglected) - Paleon Test Site 5
# This script uses startdate/enddate to create a cert with past expiration

set -euo pipefail

# Configuration
DOMAIN="${1:-paleon-lab-msp.com}"
HOSTNAME="clientc.${DOMAIN}"
# Certificate valid from 30 days ago to 1 day ago (expired)
OUTPUT_DIR="$(dirname "$0")/../../tmp/certs/clientc"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Generating EXPIRED certificate for ${HOSTNAME}"
log "  notBefore: 30 days ago"
log "  notAfter:  1 day ago (EXPIRED)"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Generate private key
log "Generating private key..."
openssl genrsa -out "${OUTPUT_DIR}/${HOSTNAME}.key" 2048

# Calculate dates for OpenSSL
# OpenSSL expects format: YYMMDDHHMMSSZ
# notBefore: 30 days ago
# notAfter: 1 day ago
START_DATE=$(date -d '30 days ago' +'%Y%m%d%H%M%S')Z 2>/dev/null || date -v-30d +'%Y%m%d%H%M%S'Z 2>/dev/null
END_DATE=$(date -d '1 day ago' +'%Y%m%d%H%M%S')Z 2>/dev/null || date -v-1d +'%Y%m%d%H%M%S'Z 2>/dev/null

# Convert to OpenSSL format (YYMMDDHHMMSSZ)
OPENSSL_STARTDATE=$(date -d '30 days ago' +'%y%m%d%H%M%S')Z 2>/dev/null || date -v-30d +'%y%m%d%H%M%S'Z 2>/dev/null
OPENSSL_ENDDATE=$(date -d '1 day ago' +'%y%m%d%H%M%S')Z 2>/dev/null || date -v-1d +'%y%m%d%H%M%S'Z 2>/dev/null

log "OpenSSL startdate: ${OPENSSL_STARTDATE}"
log "OpenSSL enddate:   ${OPENSSL_ENDDATE}"

# Generate self-signed certificate with explicit dates
# Use -days -1 with -startdate and -enddate to create expired cert
log "Generating expired self-signed certificate..."
openssl req -x509 -new -key "${OUTPUT_DIR}/${HOSTNAME}.key" \
  -out "${OUTPUT_DIR}/${HOSTNAME}.crt" \
  -days -1 \
  -subj "/CN=${HOSTNAME}" \
  -addext "subjectAltName=DNS:${HOSTNAME}" \
  -startdate "${OPENSSL_STARTDATE}" \
  -enddate "${OPENSSL_ENDDATE}"

# Set permissions
chmod 640 "${OUTPUT_DIR}/${HOSTNAME}.key"
chmod 644 "${OUTPUT_DIR}/${HOSTNAME}.crt"

# Verify
log "Certificate details:"
openssl x509 -in "${OUTPUT_DIR}/${HOSTNAME}.crt" -noout -dates -subject -issuer

# Double-check expiration
EXPIRY=$(openssl x509 -in "${OUTPUT_DIR}/${HOSTNAME}.crt" -noout -enddate | cut -d= -f2)
log "Certificate notAfter: ${EXPIRY}"

NOW=$(date +%s)
EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "${EXPIRY}" +%s 2>/dev/null)

if [[ $EXPIRY_EPOCH -lt $NOW ]]; then
  DAYS_EXPIRED=$(( (NOW - EXPIRY_EPOCH) / 86400 ))
  log "CONFIRMED: Certificate is EXPIRED by ${DAYS_EXPIRED} day(s)"
else
  log "WARNING: Certificate appears to NOT be expired!"
fi

log ""
log "Certificate generated in ${OUTPUT_DIR}/"
log "  Private key: ${HOSTNAME}.key"
log "  Certificate: ${HOSTNAME}.crt"
log ""
log "To use in nginx, copy to /etc/ssl/certs/ on the server:"
log "  cp ${OUTPUT_DIR}/${HOSTNAME}.crt /etc/ssl/certs/"
log "  cp ${OUTPUT_DIR}/${HOSTNAME}.key /etc/ssl/certs/"
log "  chmod 640 /etc/ssl/certs/${HOSTNAME}.key"
log "  chmod 644 /etc/ssl/certs/${HOSTNAME}.crt"