# Port Map — Paleon Test Site 5

## Overview

This document defines the exact port exposure for the MSP test site. The scanner performs TCP-connect scans across common ports; this map ensures deterministic results.

---

## Public Ports (Internet-Facing)

| Port | Protocol | Service | Exposure | Client | Purpose |
|------|----------|---------|----------|--------|---------|
| 80 | TCP | HTTP | **Public (0.0.0.0/0)** | All | HTTP redirect to HTTPS |
| 443 | TCP | HTTPS | **Public (0.0.0.0/0)** | All | Primary web service |
| 5432 | TCP | PostgreSQL | **Public (0.0.0.0/0)** | **Client C only** | **Intentional dummy listener** |

---

## Management Ports (Restricted)

| Port | Protocol | Service | Exposure | Purpose |
|------|----------|---------|----------|---------|
| 22 | TCP | SSH | **admin_ip_cidr only** | Instance management |

---

## Explicitly CLOSED Ports (Scanner Verification)

The following common scanner ports MUST remain closed (no listener, security group deny):

| Port | Service | Reason |
|------|---------|--------|
| 21 | FTP | Not used |
| 23 | Telnet | Not used |
| 25 | SMTP | Not used |
| 110 | POP3 | Not used |
| 143 | IMAP | Not used |
| 445 | SMB | Not used |
| 3389 | RDP | Not used |
| 5900 | VNC | Not used |
| 6379 | Redis | Not used |
| 8080 | HTTP Alt | Not used |
| 8443 | HTTPS Alt | Not used |
| 27017 | MongoDB | Not used |

---

## Security Group Rules (Terraform)

```hcl
# Public HTTP
ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTP redirect"
}

# Public HTTPS
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "HTTPS"
}

# Intentional Database Port (Client C Test)
ingress {
  from_port   = 5432
  to_port     = 5432
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Dummy PostgreSQL listener for Client C test"
}

# SSH Management
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.admin_ip_cidr]
  description = "SSH restricted to admin"
}

# Implicit deny for all other ports (default security group behavior)
```

---

## Dummy Listener Details (Port 5432)

### Implementation
```bash
# Using socat (installed via user-data)
socat TCP-LISTEN:5432,fork,reuseaddr SYSTEM:'echo "PostgreSQL 14.0 (dummy)"; sleep 1'
```

### Behavior
- ✅ Accepts TCP SYN → responds SYN-ACK
- ✅ Completes 3-way handshake
- ✅ Sends banner: `PostgreSQL 14.0 (dummy)`
- ✅ Closes connection after 1 second
- ✅ No authentication, no protocol negotiation
- ✅ No data persistence
- ✅ Runs as `www-data` user via systemd

### Scanner Observation
```
Port 5432: OPEN
Banner: "PostgreSQL 14.0 (dummy)"
```

### Why Port 5432?
- Standard PostgreSQL port
- Commonly scanned
- Realistic for "neglected client with exposed database"
- Not used by any other service on this instance

---

## Verification Commands

### From Scanner Perspective

```bash
TARGET="<EIP>"

# Test open ports
for port in 80 443 5432; do
  nc -zv -w 3 $TARGET $port
done

# Test closed ports
for port in 21 23 25 110 143 445 3389 5900 6379 8080 8443 27017; do
  nc -zv -w 2 $TARGET $port 2>&1 | grep -E "succeeded|open|Connection refused|timeout"
done

# Test SSH (from authorized IP only)
nc -zv -w 3 $TARGET 22

# Verify dummy listener banner
nc -w 3 $TARGET 5432
```

### Expected Output

```
# Open ports
Connection to <EIP> 80 port [tcp/http] succeeded!
Connection to <EIP> 443 port [tcp/https] succeeded!
Connection to <EIP> 5432 port [tcp/postgresql] succeeded!
PostgreSQL 14.0 (dummy)

# Closed ports (all should show "Connection refused" or timeout)
nc: connect to <EIP> port 21 (tcp) failed: Connection refused
nc: connect to <EIP> port 23 (tcp) failed: Connection refused
...
```

---

## Nginx Listening Ports

| Config | Port | Protocol | Hostnames |
|--------|------|----------|-----------|
| HTTP Bootstrap | 80 | HTTP | All 5 hostnames |
| HTTPS Final | 443 | HTTPS | All 5 hostnames |

Nginx does NOT listen on any other ports.

---

## Systemd Services & Ports

| Service | Port | Protocol | Description |
|---------|------|----------|-------------|
| nginx | 80, 443 | TCP | Web server |
| paleon-dummy-listener | 5432 | TCP | Dummy PostgreSQL |
| sshd | 22 | TCP | SSH (restricted) |

---

## Port Binding Verification (On Instance)

```bash
# Check all listening ports
sudo ss -tlnp

# Expected output:
# State   Recv-Q Send-Q Local Address:Port   Peer Address:Port  Process
# LISTEN  0      128    0.0.0.0:22            0.0.0.0:*          sshd
# LISTEN  0      511    0.0.0.0:80            0.0.0.0:*          nginx
# LISTEN  0      511    0.0.0.0:443           0.0.0.0:*          nginx
# LISTEN  0      128    0.0.0.0:5432          0.0.0.0:*          socat
```

---

## Firewall (UFW) - Not Used

We rely **entirely on Security Groups** for port control.
UFW is NOT installed/configured to avoid confusion.

---

## Summary for expected.yaml

```yaml
# Open ports findings
- id: port-80-open
  category: open_ports
  target: "*"
  expect: "HTTP port 80 open"
  severity: info
  claim: observed

- id: port-443-open
  category: open_ports
  target: "*"
  expect: "HTTPS port 443 open"
  severity: info
  claim: observed

- id: port-5432-open
  category: open_ports
  target: clientc.paleon-lab-msp.com
  expect: "PostgreSQL port 5432 open (dummy listener)"
  severity: medium
  claim: observed

# Closed ports (must_not_flag)
must_not_flag:
  - category: open_ports
    ports: [21, 23, 25, 110, 143, 445, 3389, 5900, 6379, 8080, 8443, 27017]
    reason: "Explicitly closed by security group"
```

---

## Notes

- Port 5432 is **intentionally** open only for Client C test scenario
- The dummy listener provides a realistic "exposed database" finding
- No real database is installed or accessible
- All other database/admin ports are explicitly closed
- SSH is the only management port, restricted by CIDR