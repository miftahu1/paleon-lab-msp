#!/bin/bash
# verify.sh - Post-deployment verification for Paleon Test Site 5
# Run this script after terraform apply to verify all endpoints and findings

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration (can be overridden via environment variables)
DOMAIN="${DOMAIN:-paleon-lab-msp.com}"
EXPECTED_IP="${EXPECTED_IP:-}"
CLEAN_IP="${CLEAN_IP:-}"
CLIENTC_IP="${CLIENTC_IP:-}"
EXPECTED_CLEAN_IP="${EXPECTED_CLEAN_IP:-${CLEAN_IP:-}}"
EXPECTED_CLIENTC_IP="${EXPECTED_CLIENTC_IP:-${CLIENTC_IP:-}}"
TIMEOUT=10
VERBOSE="${VERBOSE:-false}"

# Optional external checks (disabled by default to avoid external dependencies)
# Set these to "true" in the environment to enable diagnostic checks.
ENABLE_OCSP="${ENABLE_OCSP:-false}"
ENABLE_CT="${ENABLE_CT:-false}"

if [[ -n "${EXPECTED_IP:-}" ]]; then
  read -r -a EXPECTED_IPS <<< "${EXPECTED_IP}"
  EXPECTED_CLEAN_IP="${EXPECTED_CLEAN_IP:-${EXPECTED_IPS[0]:-}}"
  EXPECTED_CLIENTC_IP="${EXPECTED_CLIENTC_IP:-${EXPECTED_IPS[1]:-}}"
fi

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARN=$((WARN + 1)); }
log_section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${CYAN}[VERBOSE]${NC} $*"
  fi
}

# Curl wrapper with consistent options
do_curl() {
  local url="$1"
  local expected_code="${2:-200}"
  local flags="${3:--sf}"

  verbose "GET $url"
  response=$(curl $flags --max-time "$TIMEOUT" -w "\n%{http_code}" "$url" 2>/dev/null || echo -e "\n000")
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)

  if [[ "$http_code" == "$expected_code" ]]; then
    echo "$body"
    return 0
  else
    verbose "Expected HTTP $expected_code, got $http_code"
    return 1
  fi
}

# Check if a header exists in response
check_header() {
  local url="$1"
  local header_name="$2"
  local expected_value="${3:-}"

  verbose "HEAD $url (checking $header_name)"
  response=$(curl -sI --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "")

  if [[ -z "$response" ]]; then
    return 1
  fi

  # Find header (case insensitive)
  header_line=$(echo "$response" | grep -i "^$header_name:" | head -1)

  if [[ -z "$header_line" ]]; then
    return 1
  fi

  if [[ -n "$expected_value" ]]; then
    if echo "$header_line" | grep -qi "$expected_value"; then
      return 0
    else
      verbose "Header value mismatch: got '$header_line', expected to contain '$expected_value'"
      return 1
    fi
  fi

  return 0
}

# Get certificate info
check_cert() {
  local hostname="$1"
  local port="${2:-443}"

  verbose "Checking certificate for $hostname:$port"
  cert_pem=$( { echo | openssl s_client -connect "$hostname:$port" -servername "$hostname" -showcerts 2>/dev/null || true; } )
  cert_pem=$(echo "$cert_pem" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' | sed -n '1,200p' )
  if [[ -z "${cert_pem}" ]]; then
    return 1
  fi
  echo "$cert_pem" | openssl x509 -noout -dates -subject -issuer -ext subjectAltName 2>/dev/null || true
  return 0
}

# Parse certificate expiration
parse_cert_expiry() {
  local cert_output="$1"
  local not_after=$(echo "$cert_output" | grep "notAfter=" | cut -d= -f2)
  if [[ -n "$not_after" ]]; then
    date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$not_after" +%s 2>/dev/null
  fi
}

# Determine certificate properties (validity, expired, self-signed)
analyze_certificate() {
  local certfile_or_pem="$1"
  local notbefore notafter subject issuer san
  # read from file or stdin
  if [[ -f "$certfile_or_pem" ]]; then
    cert_text=$(openssl x509 -in "$certfile_or_pem" -noout -dates -subject -issuer -ext subjectAltName 2>/dev/null || true)
  else
    cert_text=$(echo "$certfile_or_pem" | openssl x509 -noout -dates -subject -issuer -ext subjectAltName 2>/dev/null || true)
  fi

  notbefore=$(echo "$cert_text" | grep "notBefore=" | cut -d= -f2- || true)
  notafter=$(echo "$cert_text" | grep "notAfter=" | cut -d= -f2- || true)
  subject=$(echo "$cert_text" | grep "subject=" | sed -E 's/^subject=//' | sed -e 's/^[[:space:]]*//')
  issuer=$(echo "$cert_text" | grep "issuer=" | sed -E 's/^issuer=//' | sed -e 's/^[[:space:]]*//')
  san=$(echo "$cert_text" | sed -n '/X509v3 Subject Alternative Name:/,/^$/p' | tr -d '\n' | sed -e 's/X509v3 Subject Alternative Name://')

  # expiry handling
  if [[ -n "$notafter" ]]; then
    expiry_epoch=$(date -d "$notafter" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$notafter" +%s 2>/dev/null || echo 0)
  else
    expiry_epoch=0
  fi

  now=$(date +%s)
  expired=false
  expiring=false
  if [[ $expiry_epoch -gt 0 ]]; then
    if [[ $expiry_epoch -lt $now ]]; then
      expired=true
    elif [[ $((expiry_epoch - now)) -le $((10*24*3600)) ]]; then
      expiring=true
    fi
  fi

  # self-signed detection: subject equals issuer
  self_signed=false
  if [[ -n "$subject" && -n "$issuer" ]]; then
    if [[ "$subject" == "$issuer" ]]; then
      self_signed=true
    fi
  fi

  # Print a concise summary to stdout for caller
  echo "notBefore=$notbefore"
  echo "notAfter=$notafter"
  echo "subject=$subject"
  echo "issuer=$issuer"
  echo "san=$san"
  echo "expired=$expired"
  echo "expiring=$expiring"
  echo "self_signed=$self_signed"
}
# ============================================================================
# VERIFICATION START
# ============================================================================

echo "====================================================================="
echo "Paleon Test Site 5 - Post-Deployment Verification"
echo "====================================================================="
echo "Domain: $DOMAIN"
if [[ -n "${EXPECTED_CLEAN_IP:-}" || -n "${EXPECTED_CLIENTC_IP:-}" ]]; then
  echo "Expected clean IP: ${EXPECTED_CLEAN_IP:-<unset>}"
  echo "Expected clientc IP: ${EXPECTED_CLIENTC_IP:-<unset>}"
fi
echo "Timestamp: $(date)"
echo ""

# Check required tools
for tool in curl dig openssl nc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_fail "Required tool not found: $tool"
    exit 1
  fi
done

HOSTNAMES=("msp" "clienta" "clientb" "clientc" "clientd")
FQDNS=()
for h in "${HOSTNAMES[@]}"; do
  FQDNS+=("${h}.${DOMAIN}")
done

# --- 1. DNS Resolution ---
log_section "DNS Resolution"

# Ensure expected IPs are defined safely before use
if [[ -z "${EXPECTED_CLEAN_IP:-}" || -z "${EXPECTED_CLIENTC_IP:-}" ]]; then
  log_fail "EXPECTED_CLEAN_IP and EXPECTED_CLIENTC_IP must be set (export or pass via env)"
  exit 1
fi

for fqdn in "${FQDNS[@]}"; do
  log_info "Resolving $fqdn..."
  resolved=$(dig +short "$fqdn" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)

  if [[ -z "$resolved" ]]; then
    log_fail "$fqdn - No A record found"
    continue
  fi

  # Determine expected IP per-host
  case "$fqdn" in
    "msp.$DOMAIN"|"clienta.$DOMAIN"|"clientb.$DOMAIN"|"clientd.$DOMAIN")
      expect_ip="$EXPECTED_CLEAN_IP" ;;
    "clientc.$DOMAIN")
      expect_ip="$EXPECTED_CLIENTC_IP" ;;
    *)
      expect_ip="" ;;
  esac

  if [[ -n "$expect_ip" && "$resolved" != "$expect_ip" ]]; then
    log_fail "$fqdn -> $resolved (expected $expect_ip)"
  else
    log_pass "$fqdn -> $resolved"
  fi
done

# --- 2. HTTP to HTTPS Redirect ---
log_section "HTTP to HTTPS Redirect (Port 80)"

for fqdn in "${FQDNS[@]}"; do
  log_info "Testing HTTP redirect for $fqdn..."
  response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "http://$fqdn" 2>/dev/null || echo "000")

  if [[ "$response" =~ ^30[12]$ ]]; then
    location=$(curl -sI --max-time "$TIMEOUT" "http://$fqdn" 2>/dev/null | grep -i "^location:" | head -1 | tr -d '\r')
    if echo "$location" | grep -q "https://$fqdn"; then
      log_pass "$fqdn - HTTP redirects to HTTPS ($response)"
    else
      log_warn "$fqdn - HTTP redirects but Location header may be wrong: $location"
    fi
  else
    log_fail "$fqdn - HTTP does not redirect (got $response)"
  fi
done

# --- 3. HTTPS Endpoint Availability ---
log_section "HTTPS Endpoint Availability (Port 443)"

for fqdn in "${FQDNS[@]}"; do
  log_info "Testing HTTPS for $fqdn..."
  if do_curl "https://$fqdn" 200 >/dev/null; then
    log_pass "$fqdn - HTTPS responds with 200"
  else
    log_fail "$fqdn - HTTPS not accessible or non-200 response"
  fi
done

# --- 4. Security Headers Verification ---
log_section "Security Headers Verification"

# Expected headers per host
declare -A EXPECTED_HEADERS
EXPECTED_HEADERS["msp.$DOMAIN"]="Strict-Transport-Security Content-Security-Policy X-Frame-Options X-Content-Type-Options Referrer-Policy Permissions-Policy"
EXPECTED_HEADERS["clienta.$DOMAIN"]="Strict-Transport-Security Content-Security-Policy X-Frame-Options X-Content-Type-Options Referrer-Policy Permissions-Policy"
EXPECTED_HEADERS["clientb.$DOMAIN"]="Strict-Transport-Security Content-Security-Policy X-Frame-Options Referrer-Policy Permissions-Policy"
EXPECTED_HEADERS["clientc.$DOMAIN"]="X-Frame-Options X-Content-Type-Options Referrer-Policy Permissions-Policy"
EXPECTED_HEADERS["clientd.$DOMAIN"]="Strict-Transport-Security Content-Security-Policy X-Frame-Options X-Content-Type-Options Referrer-Policy Permissions-Policy"

# Headers that MUST be missing
declare -A MISSING_HEADERS
MISSING_HEADERS["clientb.$DOMAIN"]="X-Content-Type-Options"
MISSING_HEADERS["clientc.$DOMAIN"]="Strict-Transport-Security Content-Security-Policy"

for fqdn in "${FQDNS[@]}"; do
  log_info "Checking headers for $fqdn..."

  expected="${EXPECTED_HEADERS[$fqdn]}"
  missing="${MISSING_HEADERS[$fqdn]:-}"

  for header in $expected; do
    if check_header "https://$fqdn" "$header"; then
      log_pass "$fqdn - Header present: $header"
    else
      log_fail "$fqdn - Header MISSING: $header"
    fi
  done

  for header in $missing; do
    if check_header "https://$fqdn" "$header"; then
      log_fail "$fqdn - Header PRESENT but should be MISSING: $header"
    else
      log_pass "$fqdn - Header correctly missing: $header"
    fi
  done
done

# --- 5. TLS Certificate Verification ---
log_section "TLS Certificate Verification"

for fqdn in "${FQDNS[@]}"; do
  log_info "Checking certificate for $fqdn..."

  cert_info=$(check_cert "$fqdn")

  if [[ -z "$cert_info" ]]; then
    log_fail "$fqdn - Could not retrieve certificate"
    continue
  fi

  verbose "Certificate info:\n$cert_info"

  # Check expiration
  expiry_epoch=$(parse_cert_expiry "$cert_info")
  now_epoch=$(date +%s)
  days_until_expiry=$(( (expiry_epoch - now_epoch) / 86400 ))

  case "$fqdn" in
    "clientb.$DOMAIN")
      if [[ $days_until_expiry -gt 0 && $days_until_expiry -le 15 ]]; then
        log_pass "$fqdn - Certificate expiring in ~$days_until_expiry days (expected ~10)"
      elif [[ $days_until_expiry -le 0 ]]; then
        log_fail "$fqdn - Certificate already expired (expected expiring in ~10 days)"
      else
        log_warn "$fqdn - Certificate expires in $days_until_expiry days (expected ~10)"
      fi
      ;;
    "clientc.$DOMAIN")
      if [[ $days_until_expiry -lt 0 ]]; then
        log_pass "$fqdn - Certificate expired $(( -days_until_expiry )) days ago (expected)"
      else
        log_fail "$fqdn - Certificate not expired (expires in $days_until_expiry days)"
      fi
      ;;
    *)
      if [[ $days_until_expiry -gt 30 ]]; then
        log_pass "$fqdn - Certificate valid for $days_until_expiry days"
      elif [[ $days_until_expiry -gt 0 ]]; then
        log_warn "$fqdn - Certificate expires soon ($days_until_expiry days)"
      else
        log_fail "$fqdn - Certificate expired"
      fi
      ;;
  esac

  # Check issuer
  if echo "$cert_info" | grep -q "Let's Encrypt"; then
    if [[ "$fqdn" == "msp.$DOMAIN" || "$fqdn" == "clienta.$DOMAIN" || "$fqdn" == "clientd.$DOMAIN" ]]; then
      log_pass "$fqdn - Let's Encrypt certificate (expected)"
    else
      log_warn "$fqdn - Let's Encrypt certificate (unexpected for this host)"
    fi
  elif echo "$cert_info" | grep -q "self-signed\|CN=$fqdn"; then
    if [[ "$fqdn" == "clientb.$DOMAIN" || "$fqdn" == "clientc.$DOMAIN" ]]; then
      log_pass "$fqdn - Self-signed certificate (expected)"
    else
      log_warn "$fqdn - Self-signed certificate (unexpected for this host)"
    fi
  fi
done

# --- 6. Exposed Files Check (Client C) ---
log_section "Exposed Files Check (Client C)"

CLIENTC="clientc.$DOMAIN"

log_info "Checking .git/HEAD exposure..."
if body=$(do_curl "https://$CLIENTC/.git/HEAD" 200 2>/dev/null); then
  if echo "$body" | grep -q "ref: refs/heads/main"; then
    log_pass "clientc - .git/HEAD accessible and contains correct ref"
  else
    log_warn "clientc - .git/HEAD accessible but content unexpected: $body"
  fi
else
  log_fail "clientc - .git/HEAD not accessible (should return 200)"
fi

log_info "Checking .git/config exposure..."
if body=$(do_curl "https://$CLIENTC/.git/config" 200 2>/dev/null); then
  if echo "$body" | grep -q "github.com/meridian-consulting/internal-docs.git"; then
    log_pass "clientc - .git/config accessible and contains expected remote"
  else
    log_warn "clientc - .git/config accessible but content unexpected"
  fi
else
  log_fail "clientc - .git/config not accessible (should return 200)"
fi

# Verify other hosts DON'T expose .git
for fqdn in "msp.$DOMAIN" "clienta.$DOMAIN" "clientb.$DOMAIN" "clientd.$DOMAIN"; do
  log_info "Verifying $fqdn does NOT expose .git..."
  for path in "/.git/HEAD" "/.git/config"; do
    response=$(curl -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" "https://$fqdn$path" 2>/dev/null || echo "000")
    if [[ "$response" == "404" || "$response" == "403" ]]; then
      log_pass "$fqdn - $path correctly blocked ($response)"
    elif [[ "$response" == "200" ]]; then
      log_fail "$fqdn - $path accessible (should be blocked)"
    else
      log_warn "$fqdn - $path returned $response"
    fi
  done
done

# --- 7. Port Scanning ---
log_section "Port Verification"

if [[ -n "$EXPECTED_CLEAN_IP" || -n "$EXPECTED_CLIENTC_IP" ]]; then
  CLEAN_TARGET_IP="${EXPECTED_CLEAN_IP:-$(dig +short "msp.$DOMAIN" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)}"
  CLIENTC_TARGET_IP="${EXPECTED_CLIENTC_IP:-$(dig +short "clientc.$DOMAIN" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)}"
else
  CLEAN_TARGET_IP=$(dig +short "msp.$DOMAIN" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
  CLIENTC_TARGET_IP=$(dig +short "clientc.$DOMAIN" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
fi

if [[ -n "$CLEAN_TARGET_IP" ]]; then
  log_info "Scanning clean host ports on $CLEAN_TARGET_IP..."

  for port in 80 443; do
    if nc -z -w 3 "$CLEAN_TARGET_IP" "$port" 2>/dev/null; then
      log_pass "Port $port - OPEN on clean IP $CLEAN_TARGET_IP"
    else
      log_fail "Port $port - CLOSED on clean IP $CLEAN_TARGET_IP (expected open)"
    fi
  done

  CLOSED_PORTS=(21 22 23 25 110 143 445 3389 5900 6379 8080 8443 27017)
  for port in "${CLOSED_PORTS[@]}"; do
    if nc -z -w 2 "$CLEAN_TARGET_IP" "$port" 2>/dev/null; then
      if [[ $port -eq 22 ]]; then
        log_warn "Port 22 (SSH) - OPEN on clean IP (may be restricted by SG to admin IP)"
      else
        log_fail "Port $port - OPEN on clean IP $CLEAN_TARGET_IP (should be closed)"
      fi
    else
      log_pass "Port $port - CLOSED on clean IP $CLEAN_TARGET_IP"
    fi
  done
else
  log_warn "Could not determine clean target IP for port scan"
fi

if [[ -n "$CLIENTC_TARGET_IP" ]]; then
  log_info "Scanning Client C ports on $CLIENTC_TARGET_IP..."

  for port in 80 443 5432; do
    if nc -z -w 3 "$CLIENTC_TARGET_IP" "$port" 2>/dev/null; then
      log_pass "Port $port - OPEN on Client C IP $CLIENTC_TARGET_IP"
    else
      log_fail "Port $port - CLOSED on Client C IP $CLIENTC_TARGET_IP (expected open)"
    fi
  done

  banner=$(echo "" | nc -w 3 "$CLIENTC_TARGET_IP" 5432 2>/dev/null | head -1 || echo "")
  if echo "$banner" | grep -qi "PostgreSQL"; then
    log_pass "Port 5432 - Dummy listener responds with PostgreSQL banner: $banner"
  elif [[ -n "$banner" ]]; then
    log_warn "Port 5432 - Listener responds but banner unexpected: $banner"
  else
    log_fail "Port 5432 - No response from dummy listener"
  fi
else
  log_warn "Could not determine Client C target IP for port scan"
fi

# --- 8. DNS/Email Records ---
log_section "DNS/Email Records Verification"

for fqdn in "${FQDNS[@]}"; do
  log_info "Checking SPF for $fqdn..."
  spf=$(dig +short TXT "$fqdn" | grep -i "v=spf1" | head -1 | tr -d '"')
  if [[ -n "$spf" ]]; then
    if echo "$spf" | grep -q "\-all"; then
      log_pass "$fqdn - SPF: $spf (hard fail)"
    else
      log_warn "$fqdn - SPF: $spf (soft fail or neutral)"
    fi
  else
    log_fail "$fqdn - No SPF record found"
  fi

  log_info "Checking DMARC for $fqdn..."
  dmarc=$(dig +short TXT "_dmarc.$fqdn" | grep -i "v=DMARC1" | head -1 | tr -d '"')
  if [[ -n "$dmarc" ]]; then
    if echo "$dmarc" | grep -q "p=none"; then
      if [[ "$fqdn" == "clientc.$DOMAIN" ]]; then
        log_pass "$fqdn - DMARC: $dmarc (p=none as expected)"
      else
        log_warn "$fqdn - DMARC: $dmarc (p=none - should be p=reject for clean clients)"
      fi
    elif echo "$dmarc" | grep -q "p=reject"; then
      if [[ "$fqdn" != "clientc.$DOMAIN" ]]; then
        log_pass "$fqdn - DMARC: $dmarc (p=reject as expected)"
      else
        log_warn "$fqdn - DMARC: $dmarc (p=reject - expected p=none for clientc)"
      fi
    else
      log_warn "$fqdn - DMARC: $dmarc (policy unclear)"
    fi
  else
    log_fail "$fqdn - No DMARC record found"
  fi
done

# --- 9. Content Verification ---
log_section "Content Verification"

# Check ARN trap in clienta
log_info "Checking ARN false-positive trap in clienta..."
if body=$(do_curl "https://clienta.$DOMAIN/docs/api-reference.js" 200 2>/dev/null); then
  if echo "$body" | grep -q "arn:aws:iam::123456789012:role/ScannerTestRole"; then
    log_pass "clienta - ARN trap present in api-reference.js"
  else
    log_fail "clienta - ARN trap NOT found in api-reference.js"
  fi
else
  log_fail "clienta - Could not fetch api-reference.js"
fi

# Check clean clients don't have ARN trap
for fqdn in "msp.$DOMAIN" "clientb.$DOMAIN" "clientc.$DOMAIN" "clientd.$DOMAIN"; do
  if body=$(do_curl "https://$fqdn/docs/api-reference.js" 404 2>/dev/null); then
    # 404 is expected (file doesn't exist)
    log_pass "$fqdn - No api-reference.js (as expected)"
  elif body=$(do_curl "https://$fqdn/docs/api-reference.js" 200 2>/dev/null); then
    if echo "$body" | grep -q "arn:aws:iam::123456789012:role/ScannerTestRole"; then
      log_fail "$fqdn - ARN trap found where it shouldn't be"
    else
      log_pass "$fqdn - api-reference.js exists but no ARN trap"
    fi
  else
    log_pass "$fqdn - No api-reference.js accessible"
  fi
done

# --- 10. OCSP Stapling (Clean Clients) ---
if [[ "$ENABLE_OCSP" == "true" ]]; then
  log_section "OCSP Stapling Check (Clean Clients)"
  for fqdn in "msp.$DOMAIN" "clienta.$DOMAIN" "clientd.$DOMAIN"; do
    log_info "Checking OCSP stapling for $fqdn..."
    ocsp=$(echo | openssl s_client -connect "$fqdn:443" -servername "$fqdn" -status 2>/dev/null | grep -A 10 "OCSP Response" || echo "")
    if echo "$ocsp" | grep -q "Response Status: Successful"; then
      log_pass "$fqdn - OCSP stapling working"
    else
      log_warn "$fqdn - OCSP stapling not verified (may need time to populate)"
    fi
  done
else
  log_info "OCSP stapling checks are disabled by default (set ENABLE_OCSP=true to enable diagnostics)"
fi

# --- 11. Certificate Transparency (Clean Clients) ---
if [[ "$ENABLE_CT" == "true" ]]; then
  log_section "Certificate Transparency Check (Clean Clients)"
  for fqdn in "msp.$DOMAIN" "clienta.$DOMAIN" "clientd.$DOMAIN"; do
    log_info "Checking CT logs for $fqdn..."
    # Use crt.sh API
    ct_response=$(curl -s "https://crt.sh/?q=%25.$fqdn&output=json" --max-time 15 2>/dev/null || echo "[]")
    if echo "$ct_response" | grep -q "$fqdn"; then
      log_pass "$fqdn - Found in Certificate Transparency logs"
    else
      log_warn "$fqdn - Not yet found in CT logs (may take time)"
    fi
  done
else
  log_info "Certificate Transparency checks are disabled by default (set ENABLE_CT=true to enable diagnostics)"
fi

# --- SUMMARY ---
echo ""
echo "====================================================================="
echo "VERIFICATION SUMMARY"
echo "====================================================================="
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC} $FAIL"
echo ""

# Expected findings check
echo "Expected Findings Verification:"
echo "  Client B - Expiring cert (~10 days): CHECKED"
echo "  Client B - Missing X-Content-Type-Options: CHECKED"
echo "  Client C - Expired cert: CHECKED"
echo "  Client C - Missing HSTS: CHECKED"
echo "  Client C - Missing CSP: CHECKED"
echo "  Client C - DMARC p=none: CHECKED"
echo "  Client C - Exposed .git/HEAD: CHECKED"
echo "  Client C - Exposed .git/config: CHECKED"
echo "  Client C - Open port 5432: CHECKED"
echo "  Client A - ARN trap (must NOT flag): CHECKED"
echo "  Clean clients (A, D, MSP) - No findings: CHECKED"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}VERIFICATION FAILED${NC} - $FAIL checks failed"
  echo "Review the failures above and investigate."
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo -e "${YELLOW}VERIFICATION PASSED WITH WARNINGS${NC} - $WARN warnings"
  echo "Review warnings but deployment appears functional."
  exit 0
else
  echo -e "${GREEN}ALL VERIFICATIONS PASSED${NC} - Deployment verified successfully"
  exit 0
fi