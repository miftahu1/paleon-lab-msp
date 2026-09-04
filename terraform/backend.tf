# Terraform Backend Configuration
# Site 5 - MSP Multi-Client Estate
#
# IMPORTANT: This backend must be initialized AFTER the S3 bucket and DynamoDB table exist.
# Run the bootstrap-backend.sh script first, then run: terraform init

terraform {
  backend "s3" {
    bucket         = "paleon-site5-terraform-state"
    key            = "site5/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paleon-site5-terraform-locks"

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