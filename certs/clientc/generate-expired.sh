#!/bin/bash
# generate-expired.sh - Generate self-signed certificate that is ALREADY EXPIRED
# For Client C (Neglected) - Paleon Test Site 5
# This script uses startdate/enddate to create a cert with past expiration

set -euo pipefail

# Configuration
DOMAIN="${1:-paleon-lab-msp.com}"
HOSTNAME="clientc.${DOMAIN}"
OUTPUT_DIR="$(dirname "$0")/../../tmp/certs/clientc"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "Generating EXPIRED certificate for ${HOSTNAME}"
log "  notBefore: 30 days ago"
log "  notAfter:  1 day ago (EXPIRED)"

mkdir -p "${OUTPUT_DIR}"
openssl genrsa -out "${OUTPUT_DIR}/${HOSTNAME}.key" 2048 >/dev/null 2>&1

# Deterministic expired cert using CA + explicit validity window
openssl req -x509 -new -key "${OUTPUT_DIR}/${HOSTNAME}.key" \
  -out "${OUTPUT_DIR}/${HOSTNAME}.crt" \
  -days 3650 \
  -subj "/CN=${HOSTNAME}" \
  -addext "subjectAltName=DNS:${HOSTNAME}" >/dev/null 2>&1

CA_KEY="${OUTPUT_DIR}/clientc-ca.key"
CA_CERT="${OUTPUT_DIR}/clientc-ca.crt"
CSR="${OUTPUT_DIR}/${HOSTNAME}.csr"
CNF="${OUTPUT_DIR}/clientc-ca.cnf"
INDEX="${OUTPUT_DIR}/clientc-ca.index"
SERIAL="${OUTPUT_DIR}/clientc-ca.serial"

openssl genrsa -out "${CA_KEY}" 2048 >/dev/null 2>&1
openssl req -x509 -new -key "${CA_KEY}" \
  -sha256 -days 3650 \
  -subj "/CN=Paleon Client C Test Root" \
  -out "${CA_CERT}" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign" >/dev/null 2>&1

openssl req -new -key "${OUTPUT_DIR}/${HOSTNAME}.key" \
  -subj "/CN=${HOSTNAME}" \
  -addext "subjectAltName=DNS:${HOSTNAME}" \
  -out "${CSR}" >/dev/null 2>&1

cat > "${CNF}" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
private_key = ${CA_KEY}
certificate = ${CA_CERT}
database = ${INDEX}
new_certs_dir = ${OUTPUT_DIR}
serial = ${SERIAL}
default_md = sha256
policy = policy_any
x509_extensions = v3_server

[ policy_any ]
commonName = supplied

[ v3_server ]
subjectAltName = DNS:${HOSTNAME}
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

: > "${INDEX}"
printf '1000\n' > "${SERIAL}"
START_DATE=$(date -u -d '30 days ago' +'%Y%m%d%H%M%SZ')
END_DATE=$(date -u -d '1 day ago' +'%Y%m%d%H%M%SZ')
openssl ca -batch -config "${CNF}" \
  -in "${CSR}" \
  -out "${OUTPUT_DIR}/${HOSTNAME}.crt" \
  -startdate "${START_DATE}" \
  -enddate "${END_DATE}" >/dev/null 2>&1

chmod 640 "${OUTPUT_DIR}/${HOSTNAME}.key"
chmod 644 "${OUTPUT_DIR}/${HOSTNAME}.crt"

log "Certificate details:"
openssl x509 -in "${OUTPUT_DIR}/${HOSTNAME}.crt" -noout -dates -subject -issuer -ext subjectAltName

EXPIRY=$(openssl x509 -in "${OUTPUT_DIR}/${HOSTNAME}.crt" -noout -enddate | cut -d= -f2)
EXPIRY_EPOCH=$(date -d "${EXPIRY}" +%s)
NOW=$(date +%s)

if [[ "${EXPIRY_EPOCH}" -lt "${NOW}" ]]; then
  log "CONFIRMED: Certificate is expired and notAfter is in the past"
else
  log "ERROR: Generated certificate is not expired" >&2
  exit 1
fi

log "Certificate generated in ${OUTPUT_DIR}/"
log "  Private key: ${HOSTNAME}.key"
log "  Certificate: ${HOSTNAME}.crt"
