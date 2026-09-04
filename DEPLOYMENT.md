# Deployment Guide — Paleon Test Site 5

## Prerequisites

### AWS Requirements
- AWS CLI configured with appropriate credentials
- Permissions for: EC2, VPC, Route53, EIP, S3, IAM, DynamoDB
- Existing EC2 Key Pair in target region
- S3 bucket for Terraform state (or create via bootstrap)

### Local Requirements
- Terraform ≥ 1.5.0
- Bash (for validation scripts)
- Git

---

## Pre-Deployment Validation

```bash
# Run all local validation checks
./validate.sh

# Expected output: All checks pass (warnings OK for environment-specific items)
```

### What validate.sh Checks
- ✅ Required files exist
- ✅ Shell script syntax (`bash -n`)
- ✅ Terraform formatting (`terraform fmt -check`)
- ✅ Terraform validation (`terraform validate`)
- ✅ YAML syntax (`expected.yaml`)
- ✅ Git hygiene (no secrets, no state files)
- ✅ Website content completeness
- ✅ Nginx config structure

---

## Terraform Backend Setup (First Time Only)

If this is the first deployment, you need an S3 bucket for state:

```bash
# Option 1: Run bootstrap script (creates bucket, DynamoDB table)
cd terraform
./bootstrap-backend.sh

# Option 2: Manual creation
aws s3api create-bucket \
  --bucket paleon-site5-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket paleon-site5-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket paleon-site5-terraform-state \
  --server-side-encryption-configuration \
  '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

aws s3api put-public-access-block \
  --bucket paleon-site5-terraform-state \
  --public-access-block-configuration \
  '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'

# Optional: DynamoDB for state locking
aws dynamodb create-table \
  --table-name paleon-site5-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Then update `terraform/backend.tf` with your bucket name.

---

## Deployment Variables

Create a `terraform.tfvars` file (NOT committed to Git):

```hcl
# terraform/terraform.tfvars
aws_region      = "us-east-1"
domain_name     = "paleon-lab-msp.com"
ssh_key_name    = "my-existing-keypair"
admin_ip_cidr   = "203.0.113.0/24"  # Your IP /32 or CIDR
repo_url        = "https://github.com/your-org/msp.git"
```

Or pass via command line:
```bash
terraform apply \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.5/32" \
  -var="repo_url=https://github.com/user/msp.git"
```

---

## Deployment Steps

### 1. Initialize Terraform

```bash
cd terraform
terraform init
```

### 2. Validate Configuration

```bash
terraform fmt -check
terraform validate
```

### 3. Plan Deployment

```bash
terraform plan \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.5/32" \
  -var="repo_url=https://github.com/user/msp.git"
```

Review the plan carefully. Verify:
- ✅ 2 EC2 instances (t3.micro)
- ✅ 2 Elastic IPs
- ✅ 2 Security Groups
- ✅ 1 Route53 Hosted Zone + 5 A records with split EIP mapping
- ✅ 1 S3 backend (if first deploy)

### 4. Apply Deployment

```bash
terraform apply \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.5/32" \
  -var="repo_url=https://github.com/user/msp.git"
```

Type `yes` to confirm.

### 5. Wait for Bootstrap Completion

The clean instance will:
1. Boot (~2 min)
2. Install packages (~3 min)
3. Deploy clean host configs and websites (~1 min)
4. Start DNS polling (checks every 5 min)
5. Provision Let's Encrypt certificates for clean hosts (~2-5 min after DNS resolves)
6. Enable HTTPS (~1 min)

The Client C instance will:
1. Boot (~2 min)
2. Install packages (~3 min)
3. Deploy the neglected Client C site and exposed .git content
4. Load the expired self-signed certificate and open port 5432
5. Start the dummy listener and misconfigured HTTPS site

**Total time: ~10-20 minutes**

### Optional Future DNS Enhancements

This lab does not depend on registrar-managed key material; future DNS enhancements should be treated as separate work from the host security findings tracked here.

Monitor progress:
```bash
# SSH to instance (from admin_ip)
ssh -i ~/.ssh/my-key.pem ubuntu@<EIP>

# Follow bootstrap log
sudo tail -f /var/log/paleon-bootstrap.log

# Check DNS polling
sudo journalctl -u paleon-dns-poll -f

# Check certificate setup
sudo journalctl -u paleon-cert-setup -f
```

### 6. Verify Deployment

```bash
# From local machine (after DNS propagates)
cd ..
./verify.sh
```

Expected verify.sh output:
```
✅ DNS: msp.paleon-lab-msp.com resolves to EIP
✅ DNS: clienta.paleon-lab-msp.com resolves to EIP
✅ DNS: clientb.paleon-lab-msp.com resolves to EIP
✅ DNS: clientc.paleon-lab-msp.com resolves to EIP
✅ DNS: clientd.paleon-lab-msp.com resolves to EIP
✅ HTTP: All hostnames respond on port 80
✅ HTTPS: All hostnames respond on port 443
✅ Headers: Client A has full security headers
✅ Headers: Client B missing X-Content-Type-Options only
✅ Headers: Client C missing HSTS and CSP
✅ TLS: Client A valid (Let's Encrypt)
✅ TLS: Client B expiring ~10 days
✅ TLS: Client C expired
✅ TLS: Client D valid (Let's Encrypt)
✅ Files: Client C /.git/HEAD = 200
✅ Files: Client C /.git/config = 200
✅ Files: Client A /.git/HEAD = 404/403
✅ Ports: 80 open, 443 open, 5432 open, others closed
✅ DNS/Email: Client A DMARC p=reject
✅ DNS/Email: Client C DMARC p=none
✅ False-positive: Client A ARN not flagged as secret
```

---

## Post-Deployment Verification Details

### Manual Checks

```bash
# Test each hostname
for host in msp clienta clientb clientc clientd; do
  echo "=== $host.paleon-lab-msp.com ==="
  curl -I "https://$host.paleon-lab-msp.com"
  echo ""
done

# Test exposed files (Client C)
curl -I "https://clientc.paleon-lab-msp.com/.git/HEAD"
curl -I "https://clientc.paleon-lab-msp.com/.git/config"

# Test clean clients (should 404/403)
curl -I "https://clienta.paleon-lab-msp.com/.git/HEAD"
curl -I "https://clientd.paleon-lab-msp.com/.git/HEAD"

# Test TLS certificate details
openssl s_client -connect clientb.paleon-lab-msp.com:443 -servername clientb.paleon-lab-msp.com </dev/null 2>/dev/null | openssl x509 -noout -dates
openssl s_client -connect clientc.paleon-lab-msp.com:443 -servername clientc.paleon-lab-msp.com </dev/null 2>/dev/null | openssl x509 -noout -dates

# Test port 5432
nc -zv clientc.paleon-lab-msp.com 5432

# Test closed ports
for port in 21 23 25 110 143 445 3389 5900 6379 8080 8443 27017; do
  nc -zv -w 2 clientc.paleon-lab-msp.com $port 2>&1 | grep -v "succeeded\|open"
done
```

---

## Troubleshooting

### DNS Not Resolving
```bash
# Check Route53 records
aws route53 list-resource-record-sets --hosted-zone-id <ZONE_ID>

# Check split EIP mapping
dig +short msp.paleon-lab-msp.com
dig +short clientc.paleon-lab-msp.com
```

### Certificates Not Issuing
```bash
# Check certbot logs
sudo journalctl -u certbot -f

# Manual certbot test
sudo certbot certonly --nginx -d clienta.paleon-lab-msp.com --dry-run
```

### Nginx Not Reloading
```bash
# Test config
sudo nginx -t

# Check error log
sudo tail -f /var/log/nginx/error.log
```

### Dummy Listener Not Running
```bash
# Check service status
sudo systemctl status paleon-dummy-listener

# Check port
sudo ss -tlnp | grep 5432

# Manual test
socat TCP-LISTEN:5432,fork,reuseaddr SYSTEM:'echo "PostgreSQL 14.0 (dummy)"; sleep 1' &
nc -zv localhost 5432
```

---

## Updating the Deployment

### Website Content Changes
```bash
# Edit files in website/
# Commit and push to repo
git add .
git commit -m "Update client content"
git push

# Re-deploy (instance pulls on next boot, or manually)
ssh ubuntu@<EIP> "cd /opt/paleon && git pull && sudo ./redeploy-website.sh"
```

### Infrastructure Changes
```bash
cd terraform
# Edit .tf files
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

### Nginx Config Changes
```bash
# Edit nginx/http-bootstrap/ or nginx/https-final/
# Deploy via Terraform (recreates instance) or manually:
scp nginx/https-final/*.conf ubuntu@<EIP>:/etc/nginx/sites-available/
ssh ubuntu@<EIP> "sudo nginx -t && sudo systemctl reload nginx"
```

---

## Destroying the Deployment

```bash
cd terraform
terraform destroy \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.5/32" \
  -var="repo_url=https://github.com/user/msp.git"
```

**Note**: This destroys the EC2 instance, EIP, Route53 zone, and security group. S3 state bucket is NOT destroyed (manual cleanup required).

---

## Importing Existing Resources

If resources already exist:

```bash
# Import EC2 instance
terraform import aws_instance.msp i-0123456789abcdef0

# Import Elastic IP
terraform import aws_eip.msp eipalloc-0123456789abcdef0

# Import Route53 zone
terraform import aws_route53_zone.msp Z123456789ABCDEF

# Import Security Group
terraform import aws_security_group.msp sg-0123456789abcdef0
```

Then run `terraform plan` to reconcile.

---

## Environment-Specific Notes

### Using a Real Domain
If you register `paleon-lab-msp.com`:
1. Update NS records at registrar to Route53 nameservers
2. Let's Encrypt will issue valid trusted certificates

### Using a Test Domain (Current Default)
- Domain is fictional, not registered
- Route53 zone created but not delegated
- DNS resolution only works from within AWS or with custom resolver
- Self-signed certs used for all clients (or LE with DNS challenge if configured)
- Scanner must be configured to use the test DNS

### Different Region
Change `aws_region` variable. Ensure:
- Key pair exists in that region
- AMI filter works (Ubuntu 24.04 hvm-ssd-gp3 available)
- S3 bucket in same region (or update backend)

---

## Monitoring & Maintenance

### Certificate Renewal (Let's Encrypt)
- Automatic via `certbot.timer` (daily)
- Check: `systemctl list-timers | grep certbot`
- Logs: `journalctl -u certbot`

### Log Rotation
- Nginx: `/etc/logrotate.d/nginx`
- Bootstrap: `/var/log/paleon-bootstrap.log` (manual rotation)

### Health Checks
```bash
# Quick health check
curl -sf https://msp.paleon-lab-msp.com >/dev/null && echo "OK" || echo "FAIL"

# Full verification
./verify.sh
```

---

## Support & Escalation

| Issue | Action |
|-------|--------|
| Bootstrap fails | Check `/var/log/paleon-bootstrap.log` |
| DNS not propagating | Wait 5-15 min, check Route53 console |
| Certs not issuing | Verify DNS, check certbot logs |
| Port 5432 not open | Check security group, dummy listener service |
| Unexpected findings | Compare with `expected.yaml`, update if design changed |

---

## Rollback Procedure

```bash
# 1. Revert Terraform changes (if infrastructure)
cd terraform
terraform apply -var-file="terraform.tfvars"  # with previous config

# 2. Revert website content
git revert <commit>
git push
# Trigger redeploy on instance

# 3. Full redeploy (nuclear option)
terraform destroy -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

---

## Version History

See [CHANGES.md](CHANGES.md) for detailed change log.

**Current Version**: Site 5 — Initial Release (2026-09-04)