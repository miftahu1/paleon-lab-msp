#!/bin/bash
# generate-expiring.sh - Generate self-signed certificate expiring in ~10 days
# For Client B (Subtle) - Paleon Test Site 5
# This script can be run locally to generate test certificates

set -euo pipefail

# Configuration
DOMAIN="${1:-paleon-lab-msp.com}"
HOSTNAME="clientb.${DOMAIN}"
DAYS=10
OUTPUT_DIR="$(dirname "$0")/../../tmp/certs/clientb"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Generating expiring certificate for ${HOSTNAME} (valid for ${DAYS} days)"

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Generate private key
log "Generating private key..."
openssl genrsa -out "${OUTPUT_DIR}/${HOSTNAME}.key" 2048

# Generate self-signed certificate
log "Generating self-signed certificate..."
openssl req -x509 -new -key "${OUTPUT_DIR}/${HOSTNAME}.key" \
  -out "${OUTPUT_DIR}/${HOSTNAME}.crt" \
  -days "${DAYS}" \
  -subj "/CN=${HOSTNAME}" \
  -addext "subjectAltName=DNS:${HOSTNAME}"

# Set permissions
chmod 640 "${OUTPUT_DIR}/${HOSTNAME}.key"
chmod 644 "${OUTPUT_DIR}/${HOSTNAME}.crt"

# Verify
log "Certificate details:"
openssl x509 -in "${OUTPUT_DIR}/${HOSTNAME}.crt" -noout -dates -subject -issuer

log "Certificate generated in ${OUTPUT_DIR}/"
log "  Private key: ${HOSTNAME}.key"
log "  Certificate: ${HOSTNAME}.crt"
log ""
log "To use in nginx, copy to /etc/ssl/certs/ on the server:"
log "  cp ${OUTPUT_DIR}/${HOSTNAME}.crt /etc/ssl/certs/"
log "  cp ${OUTPUT_DIR}/${HOSTNAME}.key /etc/ssl/certs/"
log "  chmod 640 /etc/ssl/certs/${HOSTNAME}.key"
log "  chmod 644 /etc/ssl/certs/${HOSTNAME}.crt"