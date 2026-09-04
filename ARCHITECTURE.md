# Architecture — Paleon Test Site 5

## Overview

This document describes the technical architecture for the MSP-managed multi-client estate. The design prioritizes simplicity, reliability, and exact reproducibility of scanner-observable findings.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AWS Cloud                                       │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                        Route 53 Hosted Zone                            │  │
│  │  paleon-lab-msp.com (managed by Terraform)                             │  │
│  │  ├─ A msp.paleon-lab-msp.com        → EIP                              │  │
│  │  ├─ A clienta.paleon-lab-msp.com    → EIP                              │  │
│  │  ├─ A clientb.paleon-lab-msp.com    → EIP                              │  │
│  │  ├─ A clientc.paleon-lab-msp.com    → EIP                              │  │
│  │  └─ A clientd.paleon-lab-msp.com    → EIP                              │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      Elastic IP (EIP)                                  │  │
│  │  Static IPv4, associated with EC2 instance                             │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                    │                                         │
│                                    ▼                                         │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                    EC2 Instance (Ubuntu 24.04 LTS)                     │  │
│  │  • Instance Type: t3.micro                                            │  │
│  │  • AMI: Ubuntu 24.04 LTS (hvm-ssd-gp3)                                │  │
│  │  • IMDSv2: Required (enforced)                                        │  │
│  │  • User Data: Self-contained bootstrap                                │  │
│  │  • Security Group: See below                                          │  │
│  │  • IAM: Minimal (SSM if needed, no resource access)                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Security Group Design

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Security Group: sg-msp-site5                          │
├──────────────────┬──────────────┬────────────────┬──────────────────────────┤
│ Port             │ Protocol     │ Source         │ Purpose                  │
├──────────────────┼──────────────┼────────────────┼──────────────────────────┤
│ 22               │ TCP          │ admin_ip_cidr  │ SSH management           │
│ 80               │ TCP          │ 0.0.0.0/0      │ HTTP (redirect → HTTPS)  │
│ 443              │ TCP          │ 0.0.0.0/0      │ HTTPS                    │
│ 5432             │ TCP          │ 0.0.0.0/0      │ Dummy PostgreSQL listener│
│                  │              │                │ (Client C test only)     │
├──────────────────┼──────────────┼────────────────┼──────────────────────────┤
│ ALL OTHER        │ ANY          │ DENIED         │ Implicit deny            │
└──────────────────┴──────────────┴────────────────┴──────────────────────────┘
```

### Explicitly CLOSED Ports (Scanner Verification)
21, 23, 25, 110, 143, 445, 3389, 5900, 6379, 8080, 8443, 27017

---

## Network Architecture

### VPC & Subnet
- **VPC**: Default VPC or dedicated VPC (configurable)
- **Subnet**: Public subnet with internet gateway route
- **EIP**: Allocated and associated with instance

### IMDSv2 Enforcement
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 2
}
```

---

## Nginx Architecture

### Two-Phase Configuration Strategy

**Phase 1: HTTP Bootstrap (No Certificates Required)**
- Deployed immediately on instance boot
- Serves all hostnames on port 80
- Allows ACME challenges for Let's Encrypt
- Client C allows `.git` access in bootstrap

**Phase 2: HTTPS Final (Full TLS)**
- Activated after certificate provisioning
- Full security headers per client posture
- HSTS, CSP, etc. per design

### Virtual Host Mapping

| Hostname | Document Root | Phase 1 Config | Phase 2 Config |
|----------|---------------|----------------|----------------|
| msp.paleon-lab-msp.com | `/var/www/msp` | `msp.conf` | `msp.conf` |
| clienta.paleon-lab-msp.com | `/var/www/clienta` | `clienta.conf` | `clienta.conf` |
| clientb.paleon-lab-msp.com | `/var/www/clientb` | `clientb.conf` | `clientb.conf` |
| clientc.paleon-lab-msp.com | `/var/www/clientc` | `clientc.conf` | `clientc.conf` |
| clientd.paleon-lab-msp.com | `/var/www/clientd` | `clientd.conf` | `clientd.conf` |

---

## TLS Architecture

### Certificate Strategy by Client

| Client | Certificate Type | Validity | Source |
|--------|------------------|----------|--------|
| MSP Parent | Let's Encrypt | 90 days, auto-renew | ACME |
| Client A | Let's Encrypt | 90 days, auto-renew | ACME |
| Client B | **Self-signed** | ~10 days (expiring) | Generated on boot |
| Client C | **Self-signed** | **Expired** (past date) | Generated on boot |
| Client D | Let's Encrypt | 90 days, auto-renew | ACME |

### Why Self-Signed for B & C?

Let's Encrypt cannot issue certificates with:
- Custom expiration dates (~10 days)
- Past expiration dates (expired)

Self-signed certificates provide:
- **Deterministic, reproducible conditions** for scanner
- **No dependency on external CA** for test scenarios
- **Exact control** over notBefore/notAfter fields

### Certificate Generation

```bash
# Client B - Expiring in ~10 days
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout clientb.key -out clientb.crt \
  -days 10 -subj "/CN=clientb.paleon-lab-msp.com"

# Client C - Expired (set notAfter to past)
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout clientc.key -out clientc.crt \
  -days -1 -subj "/CN=clientc.paleon-lab-msp.com" \
  -startdate "$(date -d '30 days ago' +'%Y%m%d%H%M%S')Z" \
  -enddate "$(date -d '1 day ago' +'%Y%m%d%H%M%S')Z"
```

### TLS Handshake Observability

The scanner performs TLS handshakes and will observe:
- **Client B**: Valid chain (self-signed), but `notAfter` ≈ 10 days future → "Expiring Soon"
- **Client C**: Valid chain (self-signed), but `notAfter` in past → "Expired"
- **Clients A/D/MSP**: Valid LE chain, trusted, normal validity → "Valid"

---

## DNS Architecture

### Hosted Zone
- Created and managed by Terraform
- Domain: `paleon-lab-msp.com`
- NS records delegated (simulated - domain not actually registered)

### Record Set

| Name | Type | Value | TTL |
|------|------|-------|-----|
| msp | A | EIP | 300 |
| clienta | A | EIP | 300 |
| clientb | A | EIP | 300 |
| clientc | A | EIP | 300 |
| clientd | A | EIP | 300 |

### Email Security Records (Per-Subdomain)

Since DNS is zone-based, we use subdomain-specific records:

```
# Client A (Clean)
clienta._dmarc.paleon-lab-msp.com.  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clienta.example"
clienta.paleon-lab-msp.com.         TXT  "v=spf1 ip4:EIP -all"

# Client B (Clean)
clientb._dmarc.paleon-lab-msp.com.  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clientb.example"
clientb.paleon-lab-msp.com.         TXT  "v=spf1 ip4:EIP -all"

# Client C (Neglected - p=none)
clientc._dmarc.paleon-lab-msp.com.  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@clientc.example"
clientc.paleon-lab-msp.com.         TXT  "v=spf1 ip4:EIP -all"

# Client D (Clean)
clientd._dmarc.paleon-lab-msp.com.  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clientd.example"
clientd.paleon-lab-msp.com.         TXT  "v=spf1 ip4:EIP -all"
```

### CAA Records (Optional)
```
paleon-lab-msp.com.  CAA  0 issue "letsencrypt.org"
```

### DNSSEC
**Not enabled** — adds complexity without benefit for test purposes. Can be added if explicitly required.

---

## Dummy Database Listener (Port 5432)

### Purpose
Simulate an exposed PostgreSQL port for Client C without running a real database.

### Implementation
```bash
# Simple TCP listener using socat or netcat
# Listens on 0.0.0.0:5432, accepts connections, sends banner, closes
socat TCP-LISTEN:5432,fork,reuseaddr SYSTEM:'echo "PostgreSQL 14.0 (fake)"; sleep 1'
```

### Properties
- ✅ Accepts TCP connections (SYN → SYN-ACK → ACK)
- ✅ Returns a banner (simulates PostgreSQL greeting)
- ✅ No authentication, no protocol, no data access
- ✅ Runs as unprivileged user in systemd
- ✅ Only active for Client C test scenario
- ✅ Does not expose credentials or real data

### Systemd Unit
```ini
[Unit]
Description=Dummy PostgreSQL Listener for Client C Test
After=network.target

[Service]
Type=simple
User=www-data
ExecStart=/usr/bin/socat TCP-LISTEN:5432,fork,reuseaddr SYSTEM:'echo "PostgreSQL 14.0 (dummy)"; sleep 1'
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

---

## Bootstrap Sequence (User Data)

```
1. EC2 Instance Boots
        │
        ▼
2. Install Dependencies
   - nginx
   - certbot (Let's Encrypt)
   - socat (dummy listener)
   - curl, jq, dnsutils (validation)
   - git (clone repo)
        │
        ▼
3. Clone Repository (via repo_url variable)
        │
        ▼
4. Write Expected EIP to /etc/expected_ip
        │
        ▼
5. Deploy Website Content to /var/www/
        │
        ▼
6. Deploy HTTP Bootstrap Nginx Configs
        │
        ▼
7. Start Nginx (HTTP only)
        │
        ▼
8. Start DNS Polling Script (systemd timer)
        │
        ▼
9. [When DNS resolves] Run Certificate Setup
        │
        ▼
10. Deploy HTTPS Final Nginx Configs
        │
        ▼
11. Test & Reload Nginx
        │
        ▼
12. Enable Certbot Renewal Timer
        │
        ▼
13. Start Dummy Listener (port 5432)
        │
        ▼
14. Disable DNS Polling (success)
```

---

## File System Layout on Instance

```
/var/www/
├── msp/
│   └── index.html
├── clienta/
│   ├── index.html
│   └── docs/
│       └── api-reference.js
├── clientb/
│   └── index.html
├── clientc/
│   ├── index.html
│   └── .git/
│       ├── HEAD
│       └── config
└── clientd/
    └── index.html

/etc/nginx/
├── sites-available/
│   ├── msp.conf
│   ├── clienta.conf
│   ├── clientb.conf
│   ├── clientc.conf
│   └── clientd.conf
└── sites-enabled/ → symlinks to sites-available

/etc/ssl/certs/
├── clienta.crt / clienta.key  (LE)
├── clientb.crt / clientb.key  (self-signed, expiring)
├── clientc.crt / clientc.key  (self-signed, expired)
├── clientd.crt / clientd.key  (LE)
└── msp.crt / msp.key          (LE)

/etc/expected_ip               # Written by user-data, read by dns-poll.sh
/opt/paleon/scripts/
├── dns-poll.sh
├── cert-setup.sh
└── dummy-listener.sh
```

---

## Systemd Units

| Unit | Purpose | Trigger |
|------|---------|---------|
| `nginx.service` | Web server | Boot |
| `paleon-dns-poll.service` | DNS verification | Boot, timer |
| `paleon-dns-poll.timer` | Poll every 5 min | Boot |
| `paleon-cert-setup.service` | Certificate provisioning | DNS success |
| `paleon-dummy-listener.service` | TCP 5432 listener | Boot (after certs) |
| `certbot.timer` | LE renewal | Daily |

---

## State Management

### Terraform State
- **Backend**: S3 bucket with versioning
- **Encryption**: AES256
- **Public Access**: Blocked
- **Locking**: DynamoDB table (optional but recommended)

### Instance State
- No persistent state on instance (ephemeral)
- All config deployed via user-data
- Reset = terminate + redeploy

---

## Failure Modes & Recovery

| Failure Point | Detection | Recovery |
|---------------|-----------|----------|
| DNS not propagated | dns-poll.sh fails after 30 attempts | Wait, re-run; or check Route53 |
| LE cert fails | cert-setup.sh exits non-zero | Check logs, verify DNS, re-run |
| Nginx config invalid | `nginx -t` fails | Fix config, reload |
| Dummy listener fails | systemd status failed | Check port 5432, restart unit |
| Instance unhealthy | SSH/HTTP checks fail | Replace instance (terraform apply) |

---

## Security Considerations

1. **No Real Secrets**: All certificates, keys, tokens are test-only
2. **Minimal IAM**: Instance profile has no permissions to real resources
3. **SSH Restricted**: Only `admin_ip_cidr` can connect
4. **No Database**: Dummy listener only, no data persistence
5. **Ephemeral**: Instance can be replaced without data loss
6. **No External Calls**: Bootstrap only contacts package repos and Let's Encrypt

---

## Scalability & Extensibility

- Add clients: New subdomain, website dir, nginx config, DNS record
- Modify findings: Update website content, nginx headers, certs
- Multi-region: Duplicate module with different region variable
- Load balancer: Add ALB in front (not needed for test site)