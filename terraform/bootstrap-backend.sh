#!/bin/bash
# Terraform Backend Bootstrap Script
# Site 5 - MSP Multi-Client Estate
#
# Creates the S3 bucket used for Terraform state storage.
# This must be run before the first terraform init in a fresh AWS account.

set -euo pipefail

BUCKET_NAME="paleon-site5-terraform-state"
AWS_REGION="us-east-1"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== TERRAFORM BACKEND BOOTSTRAP ==="
log "Bucket: ${BUCKET_NAME}"
log "Region: ${AWS_REGION}"

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  log "Bucket ${BUCKET_NAME} already exists"
else
  log "Creating S3 bucket..."
  if [ "${AWS_REGION}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
  log "Bucket created"
fi

log "Enabling versioning..."
aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled

log "Enabling encryption..."
aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

log "Blocking public access..."
aws s3api put-public-access-block --bucket "${BUCKET_NAME}" --public-access-block-configuration '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'

log "=== BACKEND BOOTSTRAP COMPLETE ==="
log ""
log "Next steps:"
log "1. Ensure the bucket name matches terraform/backend.tf"
log "2. Run: terraform init"
log "3. Run: terraform plan -var-file=terraform.tfvars"
log "4. Run: terraform apply -var-file=terraform.tfvars"