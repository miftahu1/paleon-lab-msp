# Terraform Backend Configuration
# Site 5 - MSP Multi-Client Estate
#
# The S3 bucket must exist before the first terraform init.
# Run the bootstrap-backend.sh script first, then run: terraform init
# DynamoDB state locking is intentionally omitted because this lab does not need it.

terraform {
  backend "s3" {
    bucket  = "paleon-site5-terraform-state"
    key     = "site5/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true

    # Optional: Use KMS key for additional encryption
    # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/..."
  }
}

# Alternative: Local backend for development/testing only
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }