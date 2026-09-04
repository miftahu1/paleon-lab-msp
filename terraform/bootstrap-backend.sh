#!/bin/bash
# Terraform Backend Bootstrap Script
# Site 5 - MSP Multi-Client Estate
#
# Creates the S3 bucket and DynamoDB table for Terraform state storage.
# Run this ONCE before first terraform init.

set -euo pipefail

# Configuration - CHANGE THESE
BUCKET_NAME="paleon-site5-terraform-state"
DYNAMODB_TABLE="paleon-site5-terraform-locks"
AWS_REGION="us-east-1"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "=== TERRAFORM BACKEND BOOTSTRAP ==="
log "Bucket: ${BUCKET_NAME}"
log "Table: ${DYNAMODB_TABLE}"
log "Region: ${AWS_REGION}"

# Check if bucket exists
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

# Enable versioning
log "Enabling versioning..."
aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" --versioning-configuration Status=Enabled

# Enable encryption
log "Enabling encryption..."
aws s3api put-bucket-encryption --bucket "${BUCKET_NAME}" --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# Block public access
log "Blocking public access..."
aws s3api put-public-access-block --bucket "${BUCKET_NAME}" --public-access-block-configuration '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'

# Create DynamoDB table for state locking
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}" 2>/dev/null; then
  log "DynamoDB table ${DYNAMODB_TABLE} already exists"
else
  log "Creating DynamoDB table..."
  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}"

  log "Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${AWS_REGION}"
  log "Table created and active"
fi

log "=== BACKEND BOOTSTRAP COMPLETE ==="
log ""
log "Next steps:"
log "1. Update terraform/backend.tf with your bucket name if different"
log "2. Run: terraform init"
log "3. Run: terraform plan -var-file=terraform.tfvars"
log "4. Run: terraform apply -var-file=terraform.tfvars"