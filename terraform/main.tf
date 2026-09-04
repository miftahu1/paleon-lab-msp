# Main Terraform Configuration
# Site 5 - MSP Multi-Client Estate

##############################
# Provider & Data Sources
##############################

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

# Get latest Ubuntu 24.04 LTS AMI (hvm-ssd-gp3)
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Default VPC (or create dedicated if needed)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# First available subnet in default VPC
data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}

##############################
# Elastic IP
##############################

resource "aws_eip" "msp" {
  domain = "vpc"
  tags = merge(var.tags, {
    Name = "paleon-site5-eip"
  })
}

##############################
# Security Group
##############################

resource "aws_security_group" "msp" {
  name        = "paleon-site5-sg"
  description = "Security group for Paleon Site 5 MSP estate"
  vpc_id      = data.aws_vpc.default.id

  # HTTP - Public
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS"
  }

  # HTTPS - Public
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  # Intentional Database Port (PostgreSQL) - Public for Client C test
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Dummy PostgreSQL listener for Client C neglected test"
  }

  # SSH - Restricted to admin IP(s)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat([var.admin_ip_cidr], var.ssh_allowed_cidrs)
    description = "SSH management access"
  }

  # Egress - Allow all outbound (for package updates, Let's Encrypt, DNS)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, {
    Name = "paleon-site5-sg"
  })
}

##############################
# EC2 Instance
##############################

resource "aws_instance" "msp" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.msp.id]
  associate_public_ip_address = false # We use EIP

  # IMDSv2 Required
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  # Root volume
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  # User data - rendered from template
  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url    = var.repo_url
    domain_name = var.domain_name
    expected_ip = aws_eip.msp.public_ip
    aws_region  = var.aws_region
  })

  tags = merge(var.tags, {
    Name = "paleon-site5-msp"
  })

  # Ensure EIP is associated after instance creation
  depends_on = [aws_eip.msp]
}

##############################
# EIP Association
##############################

resource "aws_eip_association" "msp" {
  instance_id   = aws_instance.msp.id
  allocation_id = aws_eip.msp.id
}

##############################
# Route 53 Hosted Zone
##############################

resource "aws_route53_zone" "msp" {
  name = var.domain_name

  # DNSSEC is configured separately if needed (requires KMS key)
  # Not enabled by default for simplicity
}

##############################
# Route 53 Records
##############################

# A records for all hostnames pointing to EIP
resource "aws_route53_record" "hostnames" {
  for_each = toset([
    "msp",
    "clienta",
    "clientb",
    "clientc",
    "clientd"
  ])

  zone_id = aws_route53_zone.msp.zone_id
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [aws_eip.msp.public_ip]
}

# SPF records for each subdomain
resource "aws_route53_record" "spf" {
  for_each = toset([
    "msp",
    "clienta",
    "clientb",
    "clientc",
    "clientd"
  ])

  zone_id = aws_route53_zone.msp.zone_id
  name    = each.key
  type    = "TXT"
  ttl     = 300
  records = ["\"v=spf1 ip4:${aws_eip.msp.public_ip} -all\""]
}

# DMARC records for each subdomain
resource "aws_route53_record" "dmarc" {
  for_each = {
    msp     = "v=DMARC1; p=reject; rua=mailto:dmarc@msp.example; ruf=mailto:dmarc@msp.example; sp=reject; adkim=s; aspf=s"
    clienta = "v=DMARC1; p=reject; rua=mailto:dmarc@clienta.example; ruf=mailto:dmarc@clienta.example; sp=reject; adkim=s; aspf=s"
    clientb = "v=DMARC1; p=reject; rua=mailto:dmarc@clientb.example; ruf=mailto:dmarc@clientb.example; sp=reject; adkim=s; aspf=s"
    clientc = "v=DMARC1; p=none; rua=mailto:dmarc@clientc.example"
    clientd = "v=DMARC1; p=reject; rua=mailto:dmarc@clientd.example; ruf=mailto:dmarc@clientd.example; sp=reject; adkim=s; aspf=s"
  }

  zone_id = aws_route53_zone.msp.zone_id
  name    = "_dmarc.${each.key}"
  type    = "TXT"
  ttl     = 300
  records = ["\"${each.value}\""]
}

# CAA record (optional but recommended)
resource "aws_route53_record" "caa" {
  count = var.enable_dnssec ? 1 : 0

  zone_id = aws_route53_zone.msp.zone_id
  name    = "@"
  type    = "CAA"
  ttl     = 300
  records = ["0 issue \"letsencrypt.org\""]
}

##############################
# S3 Bucket for Terraform State (Bootstrap)
# Note: This is created separately via bootstrap script
# Included here for reference - DO NOT create if bucket exists
##############################

# resource "aws_s3_bucket" "terraform_state" {
#   bucket = "paleon-site5-terraform-state-${random_id.suffix.hex}"
#
#   server_side_encryption_configuration {
#     rule {
#       apply_server_side_encryption_by_default {
#         sse_algorithm = "AES256"
#       }
#     }
#   }
#
#   versioning {
#     enabled = true
#   }
#
#   lifecycle {
#     prevent_destroy = true
#   }
# }
#
# resource "aws_s3_bucket_public_access_block" "terraform_state" {
#   bucket = aws_s3_bucket.terraform_state.id
#
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }
#
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "paleon-site5-terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

##############################
# Random ID for unique bucket name (if needed)
##############################

resource "random_id" "suffix" {
  byte_length = 8
}