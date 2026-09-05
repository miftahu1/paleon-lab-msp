# TLS Architecture — Paleon Test Site 5

## Design Principles

1. **Deterministic Observability**: Scanner must see exactly what we intend
2. **No External Dependencies** for test scenarios (expired/expiring certs)
3. **Clean Separation**: HTTP bootstrap → DNS verification → HTTPS final
4. **Reproducible**: Same deployment = same TLS observations

---

## Certificate Strategy by Client

| Client | Certificate Type | Validity Period | Issuer | Purpose |
|--------|------------------|-----------------|--------|---------|
| MSP Parent | Let's Encrypt | 90 days, auto-renew | LE (trusted) | Clean baseline |
| Client A | Let's Encrypt | 90 days, auto-renew | LE (trusted) | Clean control |
| Client B | Self-Signed | ~10 days (expiring) | Self | Subtle finding |
| Client C | Self-Signed | **Expired** (past) | Self | Neglected finding |
| Client D | Let's Encrypt | 90 days, auto-renew | LE (trusted) | Clean control |

---

## Why Self-Signed for Client B & C?

Let's Encrypt constraints:
- Cannot set custom `notAfter` dates
- Cannot issue already-expired certificates
- Rate limits prevent rapid re-issuance for testing

Self-signed advantages:
- ✅ Exact control over `notBefore` / `notAfter`
- ✅ No external API dependency
- ✅ Instant generation on bootstrap
- ✅ Deterministic, reproducible
- ✅ Scanner observes real TLS handshake with these properties

---

## Certificate Generation

### Client B — Expiring in ~10 Days

```bash
#!/bin/bash
# certs/clientb/generate-expiring.sh

set -euo pipefail

CERT_DIR="/etc/ssl/certs"
DOMAIN="clientb.paleon-lab-msp.com"
DAYS=10

# Generate private key
openssl genrsa -out "${CERT_DIR}/${DOMAIN}.key" 2048

# Generate self-signed certificate expiring in ~10 days
openssl req -x509 -new -key "${CERT_DIR}/${DOMAIN}.key" \
  -out "${CERT_DIR}/${DOMAIN}.crt" \
  -days "${DAYS}" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}"

# Set permissions
chmod 640 "${CERT_DIR}/${DOMAIN}.key"
chmod 644 "${CERT_DIR}/${DOMAIN}.crt"
chown root:ssl-cert "${CERT_DIR}/${DOMAIN}.key" "${CERT_DIR}/${DOMAIN}.crt"

echo "Generated ${DOMAIN} certificate expiring in ${DAYS} days"
openssl x509 -in "${CERT_DIR}/${DOMAIN}.crt" -noout -dates
```

### Client C — Expired

```bash
#!/bin/bash
# certs/clientc/generate-expired.sh

set -euo pipefail

CERT_DIR="/etc/ssl/certs"
DOMAIN="clientc.paleon-lab-msp.com"

# Generate private key
openssl genrsa -out "${CERT_DIR}/${DOMAIN}.key" 2048

# Generate deterministic expired certificate using parent test CA
# This approach guarantees notAfter is in the past by using explicit
# -startdate and -enddate when signing with the CA.
# The -days -1 approach is NOT used because it is unreliable with startdate/enddate.

# 1. Create parent test CA
openssl genrsa -out "${CERT_DIR}/clientc-ca.key" 2048
openssl req -x509 -new -key "${CERT_DIR}/clientc-ca.key" \
  -sha256 -days 3650 \
  -subj "/CN=Paleon Client C Test Root" \
  -out "${CERT_DIR}/clientc-ca.crt" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

# 2. Generate CSR for clientc
openssl req -new -key "${CERT_DIR}/${DOMAIN}.key" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN}" \
  -out "${CERT_DIR}/${DOMAIN}.csr"

# 3. Create CA config
cat > "${CERT_DIR}/clientc-ca.cnf" <<EOF
[ ca ]
default_ca = CA_default

[ CA_default ]
private_key = ${CERT_DIR}/clientc-ca.key
certificate = ${CERT_DIR}/clientc-ca.crt
database = ${CERT_DIR}/clientc-ca.index
new_certs_dir = ${CERT_DIR}
serial = ${CERT_DIR}/clientc-ca.serial
default_md = sha256
policy = policy_any
x509_extensions = v3_server

[ policy_any ]
commonName = supplied

[ v3_server ]
subjectAltName = DNS:${DOMAIN}
basicConstraints = CA:FALSE
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
EOF

# 4. Initialize CA database
: > "${CERT_DIR}/clientc-ca.index"
printf '1000\n' > "${CERT_DIR}/clientc-ca.serial"

# 5. Sign with explicit validity window (notBefore: 30 days ago, notAfter: 1 day ago)
START_DATE=$(date -u -d '30 days ago' +'%Y%m%d%H%M%SZ')
END_DATE=$(date -u -d '1 day ago' +'%Y%m%d%H%M%SZ')
openssl ca -batch -config "${CERT_DIR}/clientc-ca.cnf" \
  -in "${CERT_DIR}/${DOMAIN}.csr" \
  -out "${CERT_DIR}/${DOMAIN}.crt" \
  -startdate "${START_DATE}" \
  -enddate "${END_DATE}"

# Set permissions
chmod 640 "${CERT_DIR}/${DOMAIN}.key"
chmod 644 "${CERT_DIR}/${DOMAIN}.crt"
chown root:ssl-cert "${CERT_DIR}/${DOMAIN}.key" "${CERT_DIR}/${DOMAIN}.crt" 2>/dev/null || true

echo "Generated ${DOMAIN} certificate (EXPIRED)"
openssl x509 -in "${CERT_DIR}/${DOMAIN}.crt" -noout -dates
```

### Clean Clients — Let's Encrypt

```bash
#!/bin/bash
# Part of cert-setup.sh

# For each clean domain:
certbot certonly --nginx \
  -d msp.paleon-lab-msp.com \
  -d clienta.paleon-lab-msp.com \
  -d clientd.paleon-lab-msp.com \
  --non-interactive \
  --agree-tos \
  --email admin@paleon.example \
  --redirect
```

---

## Nginx TLS Configuration

### SSL Settings (Shared)

```nginx
# /etc/nginx/snippets/ssl-params.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 10m;
```

### Per-Client Certificate Paths

```nginx
# Client A (Clean - LE)
server {
    listen 443 ssl http2;
    server_name clienta.paleon-lab-msp.com;
    ssl_certificate /etc/letsencrypt/live/clienta.paleon-lab-msp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/clienta.paleon-lab-msp.com/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;
    # ... security headers ...
}

# Client B (Subtle - Self-signed, expiring)
server {
    listen 443 ssl http2;
    server_name clientb.paleon-lab-msp.com;
    ssl_certificate /etc/ssl/certs/clientb.paleon-lab-msp.com.crt;
    ssl_certificate_key /etc/ssl/certs/clientb.paleon-lab-msp.com.key;
    include /etc/nginx/snippets/ssl-params.conf;
    # ... security headers (missing X-Content-Type-Options) ...
}

# Client C (Neglected - Self-signed, expired)
server {
    listen 443 ssl http2;
    server_name clientc.paleon-lab-msp.com;
    ssl_certificate /etc/ssl/certs/clientc.paleon-lab-msp.com.crt;
    ssl_certificate_key /etc/ssl/certs/clientc.paleon-lab-msp.com.key;
    include /etc/nginx/snippets/ssl-params.conf;
    # ... minimal headers (no HSTS, no CSP) ...
}

# Client D (Clean - LE)
server {
    listen 443 ssl http2;
    server_name clientd.paleon-lab-msp.com;
    ssl_certificate /etc/letsencrypt/live/clientd.paleon-lab-msp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/clientd.paleon-lab-msp.com/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;
    # ... security headers ...
}

# MSP Parent (Clean - LE)
server {
    listen 443 ssl http2;
    server_name msp.paleon-lab-msp.com;
    ssl_certificate /etc/letsencrypt/live/msp.paleon-lab-msp.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/msp.paleon-lab-msp.com/privkey.pem;
    include /etc/nginx/snippets/ssl-params.conf;
    # ... security headers ...
}
```

---

## Scanner TLS Observations

### What the Scanner Sees

During TLS handshake, the scanner observes:

| Client | Certificate Chain | Trust | Validity | Expected Finding |
|--------|-------------------|-------|----------|------------------|
| MSP | LE → ISRG Root X1 | Trusted | Valid (80+ days) | None |
| Client A | LE → ISRG Root X1 | Trusted | Valid (80+ days) | None |
| Client B | Self-signed | **Untrusted** | **~10 days** | **Expiring Soon (Medium)** + **Untrusted (Low)** |
| Client C | Self-signed | **Untrusted** | **Expired** | **Expired (High)** + **Untrusted (Low)** |
| Client D | LE → ISRG Root X1 | Trusted | Valid (80+ days) | None |

### Important: Untrusted Certificate Finding

**Self-signed certificates will ALSO trigger "Untrusted Certificate" findings.**

This is technically correct and unavoidable. The `expected.yaml` must account for this:

```yaml
# Client B
- id: tls-expiring-soon
  category: tls
  target: clientb.paleon-lab-msp.com
  expect: "certificate expiring within 10 days"
  severity: medium
  claim: observed

- id: tls-untrusted
  category: tls
  target: clientb.paleon-lab-msp.com
  expect: "certificate not trusted by public CA"
  severity: low
  claim: observed

# Client C
- id: tls-expired
  category: tls
  target: clientc.paleon-lab-msp.com
  expect: "certificate expired"
  severity: high
  claim: observed

- id: tls-untrusted
  category: tls
  target: clientc.paleon-lab-msp.com
  expect: "certificate not trusted by public CA"
  severity: low
  claim: observed
```

---

## Certificate Renewal

### Let's Encrypt (Clean Clients)
- Automatic via `certbot.timer` (daily check)
- Renewal threshold: 30 days before expiry
- Post-hook: `nginx -s reload`

### Self-Signed (Client B & C)
- **Not renewed** — intentional test state
- Re-generated on instance replacement
- If instance runs long enough for Client B to expire:
  - It becomes "expired" finding (documented behavior)
  - Acceptable for test site lifecycle

---

## HTTP → HTTPS Redirect

All HTTP bootstrap configs include:

```nginx
server {
    listen 80;
    server_name clienta.paleon-lab-msp.com;
    
    # ACME challenge location (for LE)
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}
```

After HTTPS setup, this config is replaced with the final HTTPS config.

---

## OCSP Stapling

Enabled for Let's Encrypt certificates:
```nginx
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;
```

Not applicable for self-signed certificates.

---

## TLS Version & Cipher Verification

```bash
# Test each client
for host in msp clienta clientb clientc clientd; do
  echo "=== $host.paleon-lab-msp.com ==="
  openssl s_client -connect ${host}.paleon-lab-msp.com:443 \
    -servername ${host}.paleon-lab-msp.com \
    -tls1_2 </dev/null 2>/dev/null | grep -E "Protocol|Cipher"
  echo ""
done
```

Expected:
- All support TLS 1.2 and 1.3
- No TLS 1.0, 1.1, SSLv2, SSLv3
- Strong cipher suites only

---

## HSTS Configuration

### Clean Clients (A, D, MSP)
```nginx
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

### Client B (Subtle)
```nginx
# HSTS PRESENT (only X-Content-Type-Options missing)
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
```

### Client C (Neglected)
```nginx
# NO HSTS header
# add_header Strict-Transport-Security ...;  # COMMENTED OUT
```

---

## CSP Configuration

### Clean Clients (A, D, MSP)
```nginx
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self';" always;
```

### Client B (Subtle)
```nginx
# CSP PRESENT (only X-Content-Type-Options missing)
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self';" always;
```

### Client C (Neglected)
```nginx
# NO CSP header
# add_header Content-Security-Policy ...;  # COMMENTED OUT
```

---

## Security Headers Summary

| Header | MSP | Client A | Client B | Client C | Client D |
|--------|-----|----------|----------|----------|----------|
| Strict-Transport-Security | ✅ | ✅ | ✅ | ❌ | ✅ |
| Content-Security-Policy | ✅ | ✅ | ✅ | ❌ | ✅ |
| X-Frame-Options | ✅ | ✅ | ✅ | ✅ | ✅ |
| X-Content-Type-Options | ✅ | ✅ | **❌** | ✅ | ✅ |
| Referrer-Policy | ✅ | ✅ | ✅ | ✅ | ✅ |
| Permissions-Policy | ✅ | ✅ | ✅ | ✅ | ✅ |

**Only Client B is missing X-Content-Type-Options.**

---

## Verification Commands

```bash
# Check certificate details
for host in msp clienta clientb clientc clientd; do
  echo "=== $host ==="
  openssl s_client -connect ${host}.paleon-lab-msp.com:443 \
    -servername ${host}.paleon-lab-msp.com </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer -subject -dates -fingerprint
  echo ""
done

# Check headers
for host in msp clienta clientb clientc clientd; do
  echo "=== $host ==="
  curl -sI "https://${host}.paleon-lab-msp.com" | grep -iE "strict-transport|content-security|x-frame|x-content|referrer|permissions"
  echo ""
done
```