#!/bin/bash
# reset.sh - Restore Paleon Test Site 5 repository to clean state
# This script ONLY affects local files - it does NOT modify AWS resources

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_pass() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Confirm before proceeding
echo "====================================================================="
echo "Paleon Test Site 5 - Repository Reset"
echo "====================================================================="
echo ""
echo "This script will:"
echo "  - Remove all local build artifacts and temporary files"
echo "  - Restore any modified tracked files to their git state"
echo "  - Clean up generated certificates and keys (in tmp/ only)"
echo "  - Remove Terraform state files (local only, preserves .terraform.lock.hcl)"
echo ""
echo "This script will NOT:"
echo "  - Destroy or modify any AWS resources"
echo "  - Modify your git commit history"
echo "  - Remove the tracked certs/ directory (contains source generator scripts)"
echo "  - Remove terraform/.terraform.lock.hcl (tracked lock file)"
echo "  - Remove untracked files that are part of the repository design"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  log_info "Reset cancelled by user"
  exit 0
fi

echo ""
log_info "Starting repository reset..."

# Track what we clean
CLEANED=0

# Function to safely clean files matching a pattern within a directory
# Uses find to avoid glob expansion issues and limit scope to this repo
clean_glob() {
  local dir="$1"
  local pattern="$2"
  local desc="$3"
  local count=0

  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  # Use find with -maxdepth to limit recursion depth for safety
  while IFS= read -r -d '' file; do
    if [[ -e "$file" ]]; then
      rm -rf "$file"
      log_pass "Removed: $file ($desc)"
      count=$((count + 1))
    fi
  done < <(find "$dir" -maxdepth 3 -name "$pattern" -print0 2>/dev/null || true)

  CLEANED=$((CLEANED + count))
}

# Function to clean a specific path if it exists (for explicit known paths)
clean_path() {
  local path="$1"
  local desc="$2"
  if [[ -e "$path" ]]; then
    rm -rf "$path"
    log_pass "Removed: $path ($desc)"
    CLEANED=$((CLEANED + 1))
  fi
}

# --- 1. Terraform local state and artifacts (preserving .terraform.lock.hcl) ---
log_info "=== Cleaning Terraform artifacts ==="
clean_path "terraform/.terraform" "Terraform provider cache"
# NOTE: terraform/.terraform.lock.hcl is TRACKED - must NOT be deleted
clean_path "terraform/terraform.tfstate" "Local Terraform state"
clean_path "terraform/terraform.tfstate.backup" "Terraform state backup"
# Safe glob cleanup for plan files within terraform/ directory
clean_glob "terraform" "*.tfplan" "Terraform plan files"
clean_path "terraform/terraform.tfvars" "Terraform variables file (if exists)"

# --- 2. Generated certificates and keys (in tmp/ only, NOT the tracked certs/ directory) ---
log_info "=== Cleaning generated certificates ==="
# The tracked certs/ directory contains SOURCE GENERATOR SCRIPTS - NEVER DELETE
# Generated runtime certificates go to tmp/ (ignored by .gitignore) or instance runtime paths
clean_path "tmp" "Generated certificates and temporary files"

# --- 3. Log files ---
log_info "=== Cleaning log files ==="
clean_glob "." "*.log" "Log files in repo root"

# --- 4. Temporary files ---
log_info "=== Cleaning temporary files ==="
clean_glob "." "*.tmp" "Temporary files"
clean_glob "." "*.bak" "Backup files"
clean_glob "." "*~" "Editor backup files"
clean_path ".DS_Store" "macOS metadata files"
clean_path "Thumbs.db" "Windows thumbnail cache"

# --- 5. IDE/Editor directories ---
log_info "=== Cleaning IDE/editor directories ==="
clean_path ".vscode" "VS Code settings (if not committed)"
clean_path ".idea" "JetBrains IDE settings"
clean_glob "." "*.swp" "Vim swap files"
clean_glob "." "*.swo" "Vim swap files"

# --- 6. Node/Python cache (if any) ---
log_info "=== Cleaning language caches ==="
clean_path "node_modules" "Node modules"
clean_path "__pycache__" "Python cache"
clean_glob "." "*.pyc" "Python compiled files"
clean_path ".pytest_cache" "Pytest cache"
clean_path ".mypy_cache" "Mypy cache"

# --- 7. Restore tracked files that may have been modified ---
log_info "=== Restoring tracked files to git state ==="
# Only restore files that are tracked and modified
if git status --porcelain 2>/dev/null | grep -q "^ M"; then
  log_warn "The following tracked files have local modifications:"
  git status --porcelain | grep "^ M" | while read -r line; do
    file=$(echo "$line" | cut -c4-)
    echo "  - $file"
  done
  read -p "Restore all modified tracked files to HEAD? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git checkout -- .
    log_pass "Restored all modified tracked files"
    CLEANED=$((CLEANED + 1))
  else
    log_info "Skipped restoring tracked files"
  fi
else
  log_pass "No tracked files modified"
fi

# --- 8. Remove untracked files that shouldn't be in repo ---
log_info "=== Checking for unexpected untracked files ==="
UNTRACKED=$(git status --porcelain 2>/dev/null | grep "^??" | cut -c4- || true)
if [[ -n "$UNTRACKED" ]]; then
  log_warn "Found untracked files (not in .gitignore):"
  echo "$UNTRACKED" | while read -r file; do
    echo "  - $file"
  done
  echo ""
  read -p "Remove these untracked files? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "$UNTRACKED" | xargs -r rm -rf
    log_pass "Removed untracked files"
    CLEANED=$((CLEANED + 1))
  else
    log_info "Kept untracked files"
  fi
else
  log_pass "No unexpected untracked files"
fi

# --- 9. Verify critical tracked files still exist ---
log_info "=== Verifying critical repository files ==="
CRITICAL_FILES=(
  "README.md"
  "ARCHITECTURE.md"
  "DEPLOYMENT.md"
  "CHANGES.md"
  "expected.yaml"
  "validate.sh"
  "reset.sh"
  "verify.sh"
  ".gitignore"
  "terraform/main.tf"
  "terraform/variables.tf"
  "terraform/outputs.tf"
  "terraform/versions.tf"
  "terraform/user_data.sh"
  "terraform/backend.tf"
  "terraform/bootstrap-backend.sh"
  "terraform/scripts/dns-poll.sh"
  "terraform/scripts/cert-setup.sh"
  "terraform/scripts/dummy-listener.sh"
  "nginx/http-bootstrap/msp.conf"
  "nginx/http-bootstrap/clienta.conf"
  "nginx/http-bootstrap/clientb.conf"
  "nginx/http-bootstrap/clientc.conf"
  "nginx/http-bootstrap/clientd.conf"
  "nginx/https-final/msp.conf"
  "nginx/https-final/clienta.conf"
  "nginx/https-final/clientb.conf"
  "nginx/https-final/clientc.conf"
  "nginx/https-final/clientd.conf"
  "nginx/snippets/ssl-params.conf"
  "website/msp/index.html"
  "website/clienta/index.html"
  "website/clienta/docs/api-reference.js"
  "website/clientb/index.html"
  "website/clientc/index.html"
  "website/clientc/.git/HEAD"
  "website/clientc/.git/config"
  "website/clientd/index.html"
  "docs/dns-records.md"
  "docs/tls-architecture.md"
  "docs/port-map.md"
  # CRITICAL: Tracked source generator scripts in certs/ directory
  "certs/clientb/generate-expiring.sh"
  "certs/clientc/generate-expired.sh"
  # CRITICAL: Terraform lock file (tracked)
  "terraform/.terraform.lock.hcl"
)

MISSING=0
for file in "${CRITICAL_FILES[@]}"; do
  if [[ ! -f "$file" ]]; then
    log_error "CRITICAL FILE MISSING: $file"
    MISSING=$((MISSING + 1))
  fi
done

if [[ $MISSING -eq 0 ]]; then
  log_pass "All critical files present"
else
  log_error "$MISSING critical files missing - repository may be corrupted"
  log_error "RESET FAILED - tracked files were deleted"
  exit 1
fi

# --- 10. Make scripts executable ---
log_info "=== Ensuring scripts are executable ==="
chmod +x validate.sh reset.sh verify.sh 2>/dev/null || true
chmod +x terraform/user_data.sh terraform/bootstrap-backend.sh 2>/dev/null || true
chmod +x terraform/scripts/*.sh 2>/dev/null || true
chmod +x certs/clientb/generate-expiring.sh certs/clientc/generate-expired.sh 2>/dev/null || true
log_pass "Scripts marked executable"

# --- SUMMARY ---
echo ""
echo "====================================================================="
echo "RESET COMPLETE"
echo "====================================================================="
echo "Items cleaned: $CLEANED"
echo "Critical files verified: $(( ${#CRITICAL_FILES[@]} - MISSING ))/${#CRITICAL_FILES[@]}"
echo ""
log_info "Repository restored to clean state"
log_info "Next steps:"
log_info "  1. Run ./validate.sh to verify everything is correct"
log_info "  2. Run terraform init (in terraform/ directory)"
log_info "  3. Run terraform plan with your variables"
echo ""