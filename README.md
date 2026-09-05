# Paleon Test Site 5 — MSP Managed Multi-Client Estate

> **Purpose**: A deployment-ready MSP-managed estate for Paleon's non-intrusive external scanner.
> **Domain**: `paleon-lab-msp.com` (fictional - not registered)
> **Status**: Pre-deployment, validated repository

---

## 🎯 Site Overview

This repository contains a complete, production-ready infrastructure-as-code deployment for an MSP (Managed Service Provider) managing multiple client subdomains. Each client demonstrates a different security posture:

| Subdomain | Client | Posture | Purpose |
|-----------|--------|---------|---------|
| `msp.paleon-lab-msp.com` | MSP Parent | Clean | Professional MSP landing page |
| `clienta.paleon-lab-msp.com` | Client A | **Clean** | Professionally managed SMB |
| `clientb.paleon-lab-msp.com` | Client B | **Subtle** | Valid TLS, one missing header, expiring cert (~10 days) |
| `clientc.paleon-lab-msp.com` | Client C | **Neglected** | Expired TLS, missing HSTS/CSP, DMARC p=none, exposed .git, open DB port |
| `clientd.paleon-lab-msp.com` | Client D | **Clean** | Second clean control client |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Route 53 Hosted Zone                         │
│  paleon-lab-msp.com                                          │
├─────────────────────────────────────────────────────────────┤
│  A Records:                                                  │
│  • msp, clienta, clientb, clientd → CLEAN EIP               │
│  • clientc → CLIENTC EIP                                     │
│  • 2 EC2 instances / 2 EIPs / 2 security groups             │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Clean EC2 (Ubuntu 24.04 LTS, t3.micro)                    │
│  • IMDSv2 required                                           │
│  • Hostnames: msp, clienta, clientb, clientd                │
│  • Nginx virtual hosts + Let's Encrypt                       │
│  • Self-signed expiring cert for Client B                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Client C EC2 (Ubuntu 24.04 LTS, t3.micro)                 │
│  • IMDSv2 required                                           │
│  • Hostname: clientc                                         │
│  • Expired self-signed cert + exposed .git + port 5432     │
│  • No public clean-host certificate issuance                │
└─────────────────────────────────────────────────────────────┘
```

---

## 📁 Repository Structure

```
msp/
├── README.md              # This file
├── ARCHITECTURE.md        # Technical architecture deep-dive
├── DEPLOYMENT.md          # Step-by-step deployment guide
├── CHANGES.md             # Change history
├── expected.yaml          # Scanner expectations (source of truth)
├── validate.sh            # Pre-deployment validation
├── reset.sh               # Reset to clean state
├── verify.sh              # Post-deployment verification
├── .gitignore             # Git exclusions
├── terraform/
│   ├── main.tf            # Core AWS resources
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   ├── versions.tf        # Provider versions
│   ├── user_data.sh       # EC2 bootstrap script
│   ├── backend.tf         # S3 state backend
│   └── scripts/
│       ├── dns-poll.sh    # DNS verification polling
│       ├── cert-setup.sh  # Certificate provisioning
│       └── dummy-listener.sh  # TCP 5432 dummy listener
├── nginx/
│   ├── http-bootstrap/    # HTTP-only configs (pre-TLS)
│   └── https-final/       # Full HTTPS configs
├── website/
│   ├── msp/               # MSP parent site
│   ├── clienta/           # Clean client (ARN trap in docs/)
│   ├── clientb/           # Subtle client
│   ├── clientc/           # Neglected client (exposed .git/)
│   └── clientd/           # Clean control client
├── certs/
│   ├── clientb/           # Expiring cert generator
│   └── clientc/           # Expired cert generator
└── docs/
    ├── dns-records.md     # DNS configuration details
    ├── tls-architecture.md # TLS design
    └── port-map.md        # Port allocation
```

---

## 🔐 Intended Findings (Scanner Expectations)

### Client B — Subtle
| Finding | Category | Severity | Details |
|---------|----------|----------|---------|
| Certificate expiring in ~10 days | TLS | Medium | Self-signed cert with intentional short validity |
| Missing `X-Content-Type-Options` header | HTTP Headers | Low | Only missing header; all others present |

### Client C — Neglected (Primary Target)
| Finding | Category | Severity | Details |
|---------|----------|----------|---------|
| Expired TLS certificate | TLS | High | Self-signed cert with past expiration |
| Missing HSTS header | HTTP Headers | Medium | No `Strict-Transport-Security` |
| Missing CSP header | HTTP Headers | Medium | No `Content-Security-Policy` |
| DMARC `p=none` | DNS/Email | Medium | Deliberate weak policy |
| Exposed `.git/HEAD` | Exposed Files | Medium | Returns 200 with content |
| Exposed `.git/config` | Exposed Files | High | Returns 200 with config |
| Open database port (5432) | Open Ports | Medium | Dummy TCP listener accepts connections |

### Client A & D — Clean (Must NOT Flag)
- Valid trusted TLS (Let's Encrypt)
- Full security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy)
- Strong SPF, DMARC `p=reject`
- No exposed files (.git, .env, backups)
- No unnecessary open ports

---

## 🛡️ False-Positive Controls

| Control | Location | Must NOT Be Flagged As |
|---------|----------|------------------------|
| ARN reference | `clienta/docs/api-reference.js` | Real secret/credential |
| Clean client TLS | `clienta`, `clientd` | TLS weakness |
| Clean client headers | `clienta`, `clientd` | Missing headers |
| Clean client DNS/email | `clienta`, `clientd` | DMARC/SPF issues |
| Clean client files | `clienta`, `clientd` | Exposed files |

> **ARN Trap**: The file contains `arn:aws:iam::123456789012:role/ScannerTestRole` — a clearly fictional, non-functional reference. Expected.yaml explicitly marks this as `must_not_flag`.

---

## 🌐 Port Map

| Port | Protocol | Exposure | Purpose |
|------|----------|----------|---------|
| 22 | TCP | Admin CIDR only | SSH management |
| 80 | TCP | Public | HTTP (redirects to HTTPS) |
| 443 | TCP | Public | HTTPS |
| 5432 | TCP | **Public (intentional)** | Dummy PostgreSQL listener (Client C only) |

**All other common scanner ports are CLOSED**: 21, 23, 25, 110, 143, 445, 3389, 5900, 6379, 8080, 8443, 27017

---

## ⚙️ Terraform Variables (Required)

| Variable | Description | Example |
|----------|-------------|---------|
| `aws_region` | AWS region | `us-east-1` |
| `domain_name` | Base domain | `paleon-lab-msp.com` |
| `ssh_key_name` | Existing EC2 key pair name | `my-keypair` |
| `admin_ip_cidr` | Admin IP for SSH | `203.0.113.0/24` |
| `repo_url` | Git repository URL | `https://github.com/miftahu1/paleon-lab-msp.git` |

---

## 🚀 Quick Start

```bash
# 1. Validate repository
./validate.sh

# 2. Initialize Terraform (first time)
cd terraform
terraform init

# 3. Plan deployment
terraform plan \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.0/24" \
  -var="repo_url=https://github.com/miftahu1/paleon-lab-msp.git"

# 4. Deploy
terraform apply \
  -var="aws_region=us-east-1" \
  -var="domain_name=paleon-lab-msp.com" \
  -var="ssh_key_name=my-key" \
  -var="admin_ip_cidr=203.0.113.0/24" \
  -var="repo_url=https://github.com/miftahu1/paleon-lab-msp.git"

# 5. Post-deployment verification
cd ..
./verify.sh
```

---

## 🔄 Reset

```bash
# Restore local repo to clean state (no AWS changes)
./reset.sh
```

---

## 📋 Validation Checklist

Run before deployment:
- [ ] `./validate.sh` — all checks pass
- [ ] `terraform fmt -check` — formatting OK
- [ ] `terraform validate` — configuration valid
- [ ] `bash -n` on all shell scripts — no syntax errors
- [ ] No real secrets in repository
- [ ] No terraform state in Git
- [ ] `expected.yaml` matches actual design

---

## ⚠️ Safety Boundaries

- **DO NOT** run `terraform apply` without reviewing the plan
- **DO NOT** purchase/configure the real domain `paleon-lab-msp.com`
- **DO NOT** modify unrelated AWS infrastructure
- **DO NOT** use real credentials or production data
- The dummy database listener on port 5432 is **harmless** — it accepts TCP connections but speaks no database protocol
- All certificates for Client B/C are self-signed test certificates
- The lab intentionally keeps the zone model simple so the scanner focuses on host posture rather than redundant zone complexity

---

## 📚 Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — Full technical architecture
- [DEPLOYMENT.md](DEPLOYMENT.md) — Detailed deployment procedures
- [CHANGES.md](CHANGES.md) — Change log
- [docs/dns-records.md](docs/dns-records.md) — DNS record details
- [docs/tls-architecture.md](docs/tls-architecture.md) — TLS design decisions
- [docs/port-map.md](docs/port-map.md) — Complete port allocation

---

## 🏷️ Version

**Site 5** — MSP Multi-Client Estate  
Built for Paleon Non-Intrusive Scanner Testing  
Last Updated: 2026-09-04