#!/bin/bash
# validate.sh - Pre-deployment validation for Paleon Test Site 5
# Run this script before terraform plan/apply to catch issues early

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $*"; PASS=$((PASS + 1)); }
log_fail() { echo -e "${RED}[FAIL]${NC} $*"; FAIL=$((FAIL + 1)); }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; WARN=$((WARN + 1)); }

check_file() {
  local file="$1"
  local desc="$2"
  if [[ -f "$file" ]]; then
    log_pass "File exists: $file ($desc)"
  else
    log_fail "Missing file: $file ($desc)"
  fi
}

check_dir() {
  local dir="$1"
  local desc="$2"
  if [[ -d "$dir" ]]; then
    log_pass "Directory exists: $dir ($desc)"
  else
    log_fail "Missing directory: $dir ($desc)"
  fi
}

check_bash_syntax() {
  local file="$1"
  if bash -n "$file" 2>/dev/null; then
    log_pass "Bash syntax OK: $file"
  else
    log_fail "Bash syntax error: $file"
    bash -n "$file" 2>&1 | head -5
  fi
}

check_yaml_syntax() {
  local file="$1"
  if command -v yq >/dev/null 2>&1; then
    if yq eval '.' "$file" >/dev/null 2>&1; then
      log_pass "YAML syntax OK: $file"
    else
      log_fail "YAML syntax error: $file"
    fi
  elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$file'))" 2>/dev/null; then
      log_pass "YAML syntax OK: $file (via python)"
    else
      log_fail "YAML syntax error: $file (via python)"
    fi
  else
    log_warn "Cannot validate YAML (yq or python3 with pyyaml not available): $file"
  fi
}

check_json_syntax() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    if jq empty "$file" 2>/dev/null; then
      log_pass "JSON syntax OK: $file"
    else
      log_fail "JSON syntax error: $file"
    fi
  else
    log_warn "Cannot validate JSON (jq not available): $file"
  fi
}

check_terraform_fmt() {
  local dir="$1"
  if command -v terraform >/dev/null 2>&1; then
    if terraform fmt -check "$dir" >/dev/null 2>&1; then
      log_pass "Terraform formatting OK: $dir"
    else
      log_fail "Terraform formatting issues: $dir"
      terraform fmt -check "$dir" 2>&1 | head -10
    fi
  else
    log_warn "Cannot check Terraform formatting (terraform not available): $dir"
  fi
}

check_terraform_validate() {
  local dir="$1"
  if command -v terraform >/dev/null 2>&1; then
    if (cd "$dir" && terraform init -backend=false >/dev/null 2>&1 && terraform validate >/dev/null 2>&1); then
      log_pass "Terraform validation OK: $dir"
    else
      log_fail "Terraform validation failed: $dir"
      (cd "$dir" && terraform validate) 2>&1 | head -15
    fi
  else
    log_warn "Cannot validate Terraform (terraform not available): $dir"
  fi
}

check_no_secrets() {
  local file="$1"
  # Check for common secret patterns
  local patterns=(
    "AKIA[0-9A-Z]{16}"
    "aws_access_key_id"
    "aws_secret_access_key"
    "-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"
    "password\s*=\s*['\"][^'\"]{8,}['\"]"
    "secret\s*=\s*['\"][^'\"]{8,}['\"]"
    "token\s*=\s*['\"][^'\"]{16,}['\"]"
  )

  local found=0
  for pattern in "${patterns[@]}"; do
    if grep -qiE "$pattern" "$file" 2>/dev/null; then
      # Allow known test/fake patterns
      if ! grep -qiE "AKIAEXAMPLE|123456789012|ScannerTestRole|FAKE|TEST|DUMMY|EXAMPLE" "$file" 2>/dev/null; then
        log_fail "Potential secret found in $file (pattern: $pattern)"
        found=$((found + 1))
      fi
    fi
  done

  if [[ $found -eq 0 ]]; then
    log_pass "No secrets detected: $file"
  fi
}

check_git_ignored() {
  # Check if terraform state or secrets are tracked
  local ignored_patterns=(
    "*.tfstate"
    "*.tfstate.*"
    ".terraform/"
    "*.pem"
    "*.key"
    "*.crt"
    "id_rsa*"
    "*.kubeconfig"
    ".aws/credentials"
  )

  local issues=0
  for pattern in "${ignored_patterns[@]}"; do
    if git ls-files | grep -qE "$pattern" 2>/dev/null; then
      log_fail "Git tracks ignored pattern: $pattern"
      issues=$((issues + 1))
    fi
  done

  if [[ $issues -eq 0 ]]; then
    log_pass "Git ignores sensitive files correctly"
  fi
}

# ============================================================================
# VALIDATION START
# ============================================================================

echo "====================================================================="
echo "Paleon Test Site 5 - Pre-Deployment Validation"
echo "====================================================================="
echo ""

# --- 1. Required Documentation Files ---
log_info "=== Checking Documentation Files ==="
check_file "README.md" "Project overview"
check_file "ARCHITECTURE.md" "Technical architecture"
check_file "DEPLOYMENT.md" "Deployment guide"
check_file "CHANGES.md" "Change log"
check_file "expected.yaml" "Scanner expectations"
check_file ".gitignore" "Git exclusions"

# --- 2. Required Directories ---
log_info "=== Checking Directory Structure ==="
check_dir "terraform" "Terraform root"
check_dir "terraform/scripts" "Terraform scripts"
check_dir "nginx/http-bootstrap" "HTTP bootstrap configs"
check_dir "nginx/https-final" "HTTPS final configs"
check_dir "nginx/snippets" "Nginx snippets"
check_dir "website/msp" "MSP website"
check_dir "website/clienta" "Client A website"
check_dir "website/clienta/docs" "Client A docs"
check_dir "website/clientb" "Client B website"
check_dir "website/clientc" "Client C website"
check_dir "website/clientc/.git" "Client C .git directory"
check_dir "website/clientd" "Client D website"
check_dir "docs" "Documentation"

# --- 3. Terraform Files ---
log_info "=== Checking Terraform Files ==="
check_file "terraform/main.tf" "Main configuration"
check_file "terraform/variables.tf" "Input variables"
check_file "terraform/outputs.tf" "Outputs"
check_file "terraform/versions.tf" "Provider versions"
check_file "terraform/user_data.sh" "EC2 user data"
check_file "terraform/backend.tf" "Backend config"
check_file "terraform/bootstrap-backend.sh" "Backend bootstrap"
check_file "terraform/scripts/dns-poll.sh" "DNS polling script"
check_file "terraform/scripts/cert-setup.sh" "Certificate setup script"
check_file "terraform/scripts/dummy-listener.sh" "Dummy listener script"

# --- 4. Nginx Configs ---
log_info "=== Checking Nginx Configurations ==="
for host in msp clienta clientb clientc clientd; do
  check_file "nginx/http-bootstrap/${host}.conf" "HTTP bootstrap for $host"
  check_file "nginx/https-final/${host}.conf" "HTTPS final for $host"
done
check_file "nginx/snippets/ssl-params.conf" "SSL parameters snippet"

# --- 5. Website Content ---
log_info "=== Checking Website Content ==="
check_file "website/msp/index.html" "MSP homepage"
check_file "website/clienta/index.html" "Client A homepage"
check_file "website/clienta/docs/api-reference.js" "Client A ARN trap"
check_file "website/clientb/index.html" "Client B homepage"
check_file "website/clientc/index.html" "Client C homepage"
check_file "website/clientc/.git/HEAD" "Client C .git/HEAD"
check_file "website/clientc/.git/config" "Client C .git/config"
check_file "website/clientd/index.html" "Client D homepage"

# --- 6. Syntax Validation ---
log_info "=== Validating Script Syntax (bash -n) ==="
# Skip user_data.sh - it's a Terraform templatefile with mixed syntax
for script in terraform/scripts/*.sh terraform/bootstrap-backend.sh; do
  check_bash_syntax "$script"
done
# Validate user_data.sh template syntax separately (check for expected Terraform placeholders)
if grep -q '\${repo_url}' terraform/user_data.sh && \
   grep -q '\${domain_name}' terraform/user_data.sh && \
   grep -q '\${expected_clean_ip}' terraform/user_data.sh && \
   grep -q '\${expected_clientc_ip}' terraform/user_data.sh && \
   grep -q '\${aws_region}' terraform/user_data.sh && \
   grep -q '\${instance_role}' terraform/user_data.sh; then
  log_pass "user_data.sh has required Terraform template variables"
else
  log_fail "user_data.sh missing required Terraform template variables"
fi

log_info "=== Validating YAML Syntax ==="
check_yaml_syntax "expected.yaml"

log_info "=== Validating Terraform ==="
check_terraform_fmt "terraform"
check_terraform_validate "terraform"

# --- 7. Security Checks ---
log_info "=== Security Checks ==="
log_info "Checking for secrets in repository..."

# Check key files for secrets
for file in \
  terraform/main.tf \
  terraform/variables.tf \
  terraform/outputs.tf \
  terraform/user_data.sh \
  terraform/scripts/*.sh \
  expected.yaml \
  website/clienta/docs/api-reference.js \
  website/clientc/.git/config; do
  if [[ -f "$file" ]]; then
    check_no_secrets "$file"
  fi
done

check_git_ignored

# --- 8. Content Validation ---
log_info "=== Validating Content Specifics ==="

# Check ARN trap exists in clienta
if grep -q "arn:aws:iam::123456789012:role/ScannerTestRole" website/clienta/docs/api-reference.js; then
  log_pass "ARN false-positive trap present in clienta/docs/api-reference.js"
else
  log_fail "ARN false-positive trap MISSING from clienta/docs/api-reference.js"
fi

# Check clientc .git files have content
if grep -q "ref: refs/heads/main" website/clientc/.git/HEAD; then
  log_pass "Client C .git/HEAD has correct content"
else
  log_fail "Client C .git/HEAD missing or incorrect content"
fi

if grep -q "github.com/meridian-consulting/internal-docs.git" website/clientc/.git/config; then
  log_pass "Client C .git/config has expected remote URL"
else
  log_fail "Client C .git/config missing or incorrect remote URL"
fi

# Check clientc nginx allows .git access only in HTTPS final, and NOT in HTTP bootstrap
if grep -q "location .*\.git/HEAD" nginx/https-final/clientc.conf && \
   grep -q "location .*\.git/config" nginx/https-final/clientc.conf; then
  log_pass "Client C HTTPS config allows .git/HEAD and .git/config"
else
  log_fail "Client C HTTPS config missing .git access configuration"
fi

if grep -q "\.git/HEAD" nginx/http-bootstrap/clientc.conf || \
   grep -q "\.git/config" nginx/http-bootstrap/clientc.conf; then
  log_fail "Client C HTTP bootstrap must NOT expose .git/HEAD or .git/config"
else
  log_pass "Client C HTTP bootstrap does not expose .git files"
fi

# Check clientb missing X-Content-Type-Options in HTTPS
if grep -q "INTENTIONALLY MISSING.*X-Content-Type-Options" nginx/https-final/clientb.conf; then
  log_pass "Client B HTTPS config intentionally missing X-Content-Type-Options"
else
  log_fail "Client B HTTPS config should intentionally miss X-Content-Type-Options"
fi

# Check clientc missing HSTS and CSP in HTTPS (check for add_header directives, not comments)
if ! grep -q 'add_header.*Strict-Transport-Security' nginx/https-final/clientc.conf && \
   ! grep -q 'add_header.*Content-Security-Policy' nginx/https-final/clientc.conf; then
  log_pass "Client C HTTPS config intentionally missing HSTS and CSP"
else
  log_fail "Client C HTTPS config should intentionally miss HSTS and CSP"
fi

# Check clean clients have full headers
for host in msp clienta clientd; do
  if grep -q "Strict-Transport-Security" nginx/https-final/${host}.conf && \
     grep -q "Content-Security-Policy" nginx/https-final/${host}.conf && \
     grep -q "X-Frame-Options" nginx/https-final/${host}.conf && \
     grep -q "X-Content-Type-Options" nginx/https-final/${host}.conf && \
     grep -q "Referrer-Policy" nginx/https-final/${host}.conf && \
     grep -q "Permissions-Policy" nginx/https-final/${host}.conf; then
    log_pass "Clean client $host has all security headers"
  else
    log_fail "Clean client $host missing some security headers"
  fi
done

# Check self-signed cert generation in user_data.sh for clientb (10 days)
if grep -q -- "-days 10" terraform/user_data.sh; then
  log_pass "Client B certificate generation uses 10-day validity"
else
  log_fail "Client B certificate should use 10-day validity"
fi

# Check expired cert generation for clientc (openssl ca with startdate/enddate, not a stale -days -1 check)
if grep -q "openssl ca" terraform/user_data.sh && \
   grep -q "startdate" terraform/user_data.sh && \
   grep -q "enddate" terraform/user_data.sh && \
   grep -q "clientc.*DOMAIN" terraform/user_data.sh; then
  log_pass "Client C certificate generation uses expired certificate technique"
else
  log_fail "Client C certificate should use expired certificate technique"
fi

# Check dummy listener script exists and uses socat
if grep -q "socat" terraform/scripts/dummy-listener.sh && \
   grep -q "5432" terraform/scripts/dummy-listener.sh && \
   grep -q "PostgreSQL" terraform/scripts/dummy-listener.sh; then
  log_pass "Dummy listener script configured for port 5432 with PostgreSQL banner"
else
  log_fail "Dummy listener script missing required configuration"
fi

# Check DNS polling script preserves the two-line expected_ip format and validates IPv4 entries
if grep -Fq 'mapfile -t EXPECTED_IPS < <(' terraform/scripts/dns-poll.sh && \
   grep -Fq 'EXPECTED_CLEAN_IP="${EXPECTED_IPS[0]}"' terraform/scripts/dns-poll.sh && \
   grep -Fq 'EXPECTED_CLIENTC_IP="${EXPECTED_IPS[1]}"' terraform/scripts/dns-poll.sh && \
   grep -Fq 'Expected clean IP is invalid:' terraform/scripts/dns-poll.sh && \
   grep -Fq 'Expected Client C IP is invalid:' terraform/scripts/dns-poll.sh && \
   grep -Fq 'MAX_ATTEMPTS=30' terraform/scripts/dns-poll.sh; then
  log_pass "DNS polling script preserves the two-line expected_ip format and validates IPv4 entries"
else
  log_fail "DNS polling script missing required expected_ip parsing and validation"
fi

# Check cert-setup.sh has Let's Encrypt for clean clients
if grep -q "certbot" terraform/scripts/cert-setup.sh && \
   grep -q "CLEAN_HOSTNAMES" terraform/scripts/cert-setup.sh && \
   grep -q "SELF_SIGNED_HOSTNAMES" terraform/scripts/cert-setup.sh; then
  log_pass "Certificate setup script handles Let's Encrypt and self-signed correctly"
else
  log_fail "Certificate setup script missing required logic"
fi

# Check user_data.sh installs required packages
if grep -q "nginx" terraform/user_data.sh && \
   grep -q "certbot" terraform/user_data.sh && \
   grep -q "socat" terraform/user_data.sh && \
   grep -q "curl" terraform/user_data.sh; then
  log_pass "User data installs all required packages"
else
  log_fail "User data missing required packages"
fi

# Check systemd units in user_data.sh
if grep -q "paleon-dns-poll.service" terraform/user_data.sh && \
   grep -q "paleon-dns-poll.timer" terraform/user_data.sh && \
   grep -q "paleon-cert-setup.service" terraform/user_data.sh && \
   grep -q "paleon-dummy-listener.service" terraform/user_data.sh; then
  log_pass "User data installs all required systemd units"
else
  log_fail "User data missing systemd unit configuration"
fi

# Check backend.tf has S3 backend config with required bucket/region data
if grep -q "backend \"s3\"" terraform/backend.tf && \
   grep -q "bucket" terraform/backend.tf && \
   grep -q "region" terraform/backend.tf; then
  log_pass "Terraform backend configured for S3 state storage"
else
  log_fail "Terraform backend missing S3 backend configuration"
fi

# Check security group allows 5432
if grep -q "5432" terraform/main.tf && \
   grep -q "Dummy PostgreSQL" terraform/main.tf; then
  log_pass "Security group allows port 5432 for dummy PostgreSQL listener"
else
  log_fail "Security group missing port 5432 rule"
fi

# Check IMDSv2 required
if grep -q "http_tokens.*required" terraform/main.tf; then
  log_pass "IMDSv2 required on EC2 instance"
else
  log_fail "IMDSv2 not required on EC2 instance"
fi

# Check Ubuntu 24.04 AMI lookup
if grep -q "ubuntu-noble-24.04" terraform/main.tf; then
  log_pass "Ubuntu 24.04 LTS AMI lookup configured"
else
  log_fail "Ubuntu 24.04 LTS AMI lookup missing"
fi

# --- 9. expected.yaml Validation ---
log_info "=== Validating expected.yaml Structure ==="
if command -v python3 >/dev/null 2>&1; then
  if python3 << 'PYEOF'
import yaml
import sys

with open('expected.yaml', 'r') as f:
    data = yaml.safe_load(f)

required_keys = ['site', 'hostnames', 'summary', 'false_positive_controls', 'port_expectations', 'certificate_expectations', 'header_expectations', 'dns_email_expectations', 'validation_rules']
for key in required_keys:
    if key not in data:
        print(f"FAIL: expected.yaml missing required key: {key}")
        sys.exit(1)

hostnames = [h['name'] for h in data['hostnames']]
expected_hostnames = [
    'msp.paleon-lab-msp.com',
    'clienta.paleon-lab-msp.com',
    'clientb.paleon-lab-msp.com',
    'clientc.paleon-lab-msp.com',
    'clientd.paleon-lab-msp.com'
]
for hn in expected_hostnames:
    if hn not in hostnames:
        print(f"FAIL: expected.yaml missing hostname: {hn}")
        sys.exit(1)

postures = {h['name']: h['posture'] for h in data['hostnames']}
assert postures['msp.paleon-lab-msp.com'] == 'clean'
assert postures['clienta.paleon-lab-msp.com'] == 'clean'
assert postures['clientb.paleon-lab-msp.com'] == 'subtle'
assert postures['clientc.paleon-lab-msp.com'] == 'neglected'
assert postures['clientd.paleon-lab-msp.com'] == 'clean'

summary = data['summary']
assert summary['total_expected_findings'] == 9
assert summary['by_category']['tls'] == 2
assert summary['by_category']['http_headers'] == 3
assert summary['by_category']['dns_email'] == 1
assert summary['by_category']['exposed_files'] == 2
assert summary['by_category']['open_ports'] == 1
assert summary['by_severity']['high'] == 2
assert summary['by_severity']['medium'] == 6
assert summary['by_severity']['low'] == 1
assert summary['by_severity']['critical'] == 0
assert summary['by_client']['clientb.paleon-lab-msp.com'] == 2
assert summary['by_client']['clientc.paleon-lab-msp.com'] == 7

print("PASS: expected.yaml structure and content validated")
PYEOF
  then
    log_pass "expected.yaml structure validated"
  else
    log_fail "expected.yaml structure validation failed"
  fi
else
  log_warn "Cannot validate expected.yaml structure (python3 not available)"
fi

# --- 10. SSL Params Check ---
log_info "=== Checking SSL Parameters ==="
if grep -q "TLSv1.2" nginx/snippets/ssl-params.conf && \
   grep -q "TLSv1.3" nginx/snippets/ssl-params.conf && \
   grep -q "ssl_ciphers" nginx/snippets/ssl-params.conf && \
   grep -q "ssl_session_cache" nginx/snippets/ssl-params.conf; then
  log_pass "SSL parameters snippet has strong TLS configuration"
else
  log_fail "SSL parameters snippet missing strong TLS configuration"
fi

# --- 11. Bootstrap location validation ---
log_info "=== Validating bootstrap location blocks ==="
for file in nginx/http-bootstrap/*.conf; do
  count=$(grep -c 'location / {' "$file" || true)
  if [[ "$count" -eq 1 ]]; then
    log_pass "$file has exactly one location / block"
  else
    log_fail "$file has $count location / blocks (expected exactly 1)"
  fi
done

# --- 12. Client C deployment and role validation ---
log_info "=== Validating Client C and role separation ==="
if [[ -f "website/clientc/.git/HEAD" && -f "website/clientc/.git/config" ]]; then
  log_pass "Client C git metadata files are present at the expected paths"
else
  log_fail "Client C git metadata files missing from expected paths"
fi

if grep -q "cp /opt/paleon/website/clientc/.git/HEAD" terraform/user_data.sh || \
   grep -q "cp /opt/paleon/website/clientc/.git/config" terraform/user_data.sh || \
   grep -q "cp -r /opt/paleon/website/clientc/.git/\. \$\{WEBSITE_ROOT\}/clientc/.git/" terraform/user_data.sh; then
  log_pass "Client C user_data deploys .git safely (explicit files or safe cp -r source/.git/. pattern)"
else
  log_fail "Client C user_data must copy only HEAD/config or use safe 'cp -r source/.git/.' pattern (avoid nested .git/.git)"
fi

clean_block=$(awk '
  /^CLEAN_HOSTNAMES=/ { in_block=1; print; next }
  in_block && /^#/ { next }
  in_block && /^SELF_SIGNED_HOSTNAMES=/ { in_block=0; exit }
  in_block { print }
' terraform/scripts/cert-setup.sh)

if printf '%s\n' "$clean_block" | grep -q 'CLEAN_HOSTNAMES=("msp" "clienta" "clientd")' && \
   printf '%s\n' "$clean_block" | grep -q 'msp' && \
   printf '%s\n' "$clean_block" | grep -q 'clienta' && \
   printf '%s\n' "$clean_block" | grep -q 'clientd' && \
   ! printf '%s\n' "$clean_block" | grep -q 'clientb' && \
   ! printf '%s\n' "$clean_block" | grep -q 'clientc' && \
   grep -q 'for host in msp clienta clientb clientd; do' terraform/user_data.sh; then
  log_pass "Clean role enables final HTTPS for msp clienta clientb clientd; certbot requests only for msp clienta clientd"
else
  log_fail "Clean role loops incorrect: user_data should enable clientb; cert-setup should not request certbot for clientb"
fi

if grep -qE "ln -sf.*clientc.conf" terraform/user_data.sh && \
   grep -qE "ln -sf.*clientc.conf" terraform/scripts/cert-setup.sh; then
  log_pass "Client C role enables clientc.conf in both bootstrap and cert-setup as expected"
else
  log_fail "Client C role must enable only clientc.conf (check ln -sf usage)"
fi

if grep -q 'systemctl enable paleon-dummy-listener.service' terraform/scripts/cert-setup.sh && \
   ! grep -q 'systemctl enable paleon-dummy-listener.service' terraform/user_data.sh && \
   ! grep -q 'systemctl start paleon-dummy-listener.service' terraform/user_data.sh; then
  log_pass "Dummy listener enabling/starting is only performed by Client C role logic"
else
  log_fail "Dummy listener must be role-gated to Client C only (enable/start should not appear in user_data.sh)"
fi

# --- 13. verify.sh variable safety ---
log_info "=== Validating verify.sh variable definitions ==="
if grep -q 'CLEAN_IP' verify.sh && grep -q 'CLIENTC_IP' verify.sh && \
   grep -q 'EXPECTED_CLEAN_IP' verify.sh && grep -q 'EXPECTED_CLIENTC_IP' verify.sh; then
  log_pass "verify.sh defines expected clean/clientc variables before use"
else
  log_fail "verify.sh is missing required clean/clientc variable definitions"
fi

if grep -q 'CLEAN_TARGET_IP' verify.sh && grep -q 'CLIENTC_TARGET_IP' verify.sh; then
  log_pass "verify.sh defines clean/clientc target variables"
else
  log_fail "verify.sh target IP variables are missing"
fi

# --- 14. reset.sh Regression Test (static analysis) ---
log_info "=== Validating reset.sh Safety (Regression Test) ==="

# Check reset.sh does NOT delete tracked certs/ directory
if grep -q 'clean_path "certs"' reset.sh; then
  log_fail "reset.sh contains dangerous 'clean_path \"certs\"' - deletes tracked certs/ directory"
else
  log_pass "reset.sh does not delete tracked certs/ directory"
fi

# Check reset.sh does NOT delete .terraform.lock.hcl
if grep -q 'clean_path "terraform/.terraform.lock.hcl"' reset.sh; then
  log_fail "reset.sh contains dangerous 'clean_path \"terraform/.terraform.lock.hcl\"' - deletes tracked lock file"
else
  log_pass "reset.sh does not delete .terraform.lock.hcl"
fi

# Check reset.sh does NOT use unsafe glob strings with rm -rf
if grep -q 'clean_path "terraform/\*.tfplan"' reset.sh || \
   grep -q 'clean_path "\*.log"' reset.sh || \
   grep -q 'clean_path "\*.tmp"' reset.sh || \
   grep -q 'clean_path "\*.bak"' reset.sh || \
   grep -q 'clean_path "\*~"' reset.sh; then
  log_fail "reset.sh uses unsafe literal glob strings with clean_path/rm -rf"
else
  log_pass "reset.sh does not use unsafe literal glob strings"
fi

# Check reset.sh uses safe find-based glob cleanup (clean_glob function)
if grep -q 'clean_glob' reset.sh; then
  log_pass "reset.sh uses safe find-based glob cleanup (clean_glob)"
else
  log_fail "reset.sh missing safe find-based glob cleanup function"
fi

# Check reset.sh verifies critical tracked files including certs generators and lock file
if grep -q 'certs/clientb/generate-expiring.sh' reset.sh && \
   grep -q 'certs/clientc/generate-expired.sh' reset.sh && \
   grep -q 'terraform/.terraform.lock.hcl' reset.sh; then
  log_pass "reset.sh verifies critical tracked files (cert generators + lock file)"
else
  log_fail "reset.sh missing verification of critical tracked files"
fi

# Check reset.sh fails if critical files are missing (exits non-zero)
if grep -q 'exit 1' reset.sh && grep -q 'CRITICAL FILE MISSING' reset.sh; then
  log_pass "reset.sh fails loudly if tracked files are missing"
else
  log_fail "reset.sh does not fail when critical files are missing"
fi

# Check reset.sh explicitly mentions preserving certs/ directory and .terraform.lock.hcl in help text
if grep -q 'tracked certs/' reset.sh && grep -q 'terraform/.terraform.lock.hcl' reset.sh; then
  log_pass "reset.sh documents preservation of certs/ directory and lock file"
else
  log_warn "reset.sh help text could better document preservation guarantees"
fi

# --- SUMMARY ---
echo ""
echo "====================================================================="
echo "VALIDATION SUMMARY"
echo "====================================================================="
echo -e "${GREEN}Passed:${NC} $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC} $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}VALIDATION FAILED${NC} - Fix the above issues before deployment"
  exit 1
elif [[ $WARN -gt 0 ]]; then
  echo -e "${YELLOW}VALIDATION PASSED WITH WARNINGS${NC} - Review warnings before deployment"
  exit 0
else
  echo -e "${GREEN}ALL VALIDATIONS PASSED${NC} - Ready for deployment"
  exit 0
fi