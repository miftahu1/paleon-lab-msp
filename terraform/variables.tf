# Terraform Input Variables
# Site 5 - MSP Multi-Client Estate

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region (e.g., us-east-1)."
  }
}

variable "domain_name" {
  description = "Base domain name for the estate (e.g., paleon-lab-msp.com)"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a valid domain name."
  }
}

variable "ssh_key_name" {
  description = "Name of existing EC2 Key Pair in the target region"
  type        = string
  validation {
    condition     = length(var.ssh_key_name) > 0
    error_message = "ssh_key_name must not be empty."
  }
}

variable "admin_ip_cidr" {
  description = "CIDR block allowed for SSH access (e.g., 203.0.113.5/32)"
  type        = string
  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}/\\d{1,2}$", var.admin_ip_cidr))
    error_message = "admin_ip_cidr must be a valid CIDR block."
  }
}

variable "repo_url" {
  description = "HTTPS URL of the Git repository to clone on bootstrap"
  type        = string
  validation {
    condition     = can(regex("^https://github\\.com/.+\\.git$", var.repo_url))
    error_message = "repo_url must be a GitHub HTTPS URL ending in .git"
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
  validation {
    condition     = contains(["t3.micro", "t3.small", "t2.micro"], var.instance_type)
    error_message = "instance_type must be t3.micro, t3.small, or t2.micro."
  }
}

variable "ssh_allowed_cidrs" {
  description = "Additional CIDR blocks for SSH access (list)"
  type        = list(string)
  default     = []
}

variable "enable_dnssec" {
  description = "Enable DNSSEC for the hosted zone (requires KMS)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "paleon-site5"
    Environment = "test"
    ManagedBy   = "terraform"
  }
}