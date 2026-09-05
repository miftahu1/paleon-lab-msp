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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_subnet" "selected" {
  id = data.aws_subnets.default.ids[0]
}

##############################
# Elastic IPs
##############################

resource "aws_eip" "clean" {
  domain = "vpc"
  tags = merge(var.tags, {
    Name = "paleon-site5-clean-eip"
  })
}

resource "aws_eip" "clientc" {
  domain = "vpc"
  tags = merge(var.tags, {
    Name = "paleon-site5-clientc-eip"
  })
}

##############################
# Security Groups
##############################

resource "aws_security_group" "clean" {
  name        = "paleon-site5-clean-sg"
  description = "Security group for the MSP and clean clients"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat([var.admin_ip_cidr], var.ssh_allowed_cidrs)
    description = "SSH management access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, {
    Name = "paleon-site5-clean-sg"
  })
}

resource "aws_security_group" "clientc" {
  name        = "paleon-site5-clientc-sg"
  description = "Security group for the neglected Client C host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP redirect to HTTPS"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Dummy PostgreSQL listener for Client C only"
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = concat([var.admin_ip_cidr], var.ssh_allowed_cidrs)
    description = "SSH management access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = merge(var.tags, {
    Name = "paleon-site5-clientc-sg"
  })
}

##############################
# EC2 Instances
##############################

resource "aws_instance" "clean" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.clean.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url            = var.repo_url
    domain_name         = var.domain_name
    expected_clean_ip   = aws_eip.clean.public_ip
    expected_clientc_ip = aws_eip.clientc.public_ip
    aws_region          = var.aws_region
    instance_role       = "clean"
  })

  tags = merge(var.tags, {
    Name = "paleon-site5-clean"
  })

  depends_on = [aws_eip.clean, aws_eip.clientc]
}

resource "aws_instance" "clientc" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = var.instance_type
  key_name                    = var.ssh_key_name
  subnet_id                   = data.aws_subnet.selected.id
  vpc_security_group_ids      = [aws_security_group.clientc.id]
  associate_public_ip_address = false

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url            = var.repo_url
    domain_name         = var.domain_name
    expected_clean_ip   = aws_eip.clean.public_ip
    expected_clientc_ip = aws_eip.clientc.public_ip
    aws_region          = var.aws_region
    instance_role       = "clientc"
  })

  tags = merge(var.tags, {
    Name = "paleon-site5-clientc"
  })

  depends_on = [aws_eip.clean, aws_eip.clientc]
}

##############################
# EIP Associations
##############################

resource "aws_eip_association" "clean" {
  instance_id   = aws_instance.clean.id
  allocation_id = aws_eip.clean.id
}

resource "aws_eip_association" "clientc" {
  instance_id   = aws_instance.clientc.id
  allocation_id = aws_eip.clientc.id
}

##############################
# Route 53 Hosted Zone
##############################

resource "aws_route53_zone" "msp" {
  name = var.domain_name
}

##############################
# Route 53 Records
##############################

resource "aws_route53_record" "hostnames" {
  for_each = {
    msp     = aws_eip.clean.public_ip
    clienta = aws_eip.clean.public_ip
    clientb = aws_eip.clean.public_ip
    clientd = aws_eip.clean.public_ip
    clientc = aws_eip.clientc.public_ip
  }

  zone_id = aws_route53_zone.msp.zone_id
  name    = each.key
  type    = "A"
  ttl     = 300
  records = [each.value]
}

resource "aws_route53_record" "spf" {
  for_each = {
    msp     = aws_eip.clean.public_ip
    clienta = aws_eip.clean.public_ip
    clientb = aws_eip.clean.public_ip
    clientd = aws_eip.clean.public_ip
    clientc = aws_eip.clientc.public_ip
  }

  zone_id = aws_route53_zone.msp.zone_id
  name    = each.key
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 ip4:${each.value} -all"]
}

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
  records = [each.value]
}

resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.msp.zone_id
  # Use empty name for zone apex (avoid creating a literal "@" subdomain)
  name = ""
  type = "CAA"
  ttl  = 300
  records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \"letsencrypt.org\""
  ]
}

##############################
# Random ID for unique bucket name (if needed)
##############################

resource "random_id" "suffix" {
  byte_length = 8
}