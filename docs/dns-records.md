# DNS Records — Paleon Test Site 5

## Hosted Zone

- **Domain**: `paleon-lab-msp.com`
- **Managed by**: Terraform (`aws_route53_zone`)
- **Delegation**: Not registered (test domain)

## A Records

The estate uses two public EIPs: one clean-instance EIP and one Client C EIP. The clean hosts share the clean EIP, while Client C resolves to its own EIP.

| Record Name | FQDN | Type | Value | TTL |
|-------------|------|------|-------|-----|
| msp | msp.paleon-lab-msp.com | A | CLEAN_EIP | 300 |
| clienta | clienta.paleon-lab-msp.com | A | CLEAN_EIP | 300 |
| clientb | clientb.paleon-lab-msp.com | A | CLEAN_EIP | 300 |
| clientd | clientd.paleon-lab-msp.com | A | CLEAN_EIP | 300 |
| clientc | clientc.paleon-lab-msp.com | A | CLIENTC_EIP | 300 |

## Email Security Records (Subdomain-Specific)

Since DNS is zone-based, we use subdomain-prefixed records for per-client email posture.

### Client A (Clean)
```
clienta._dmarc.paleon-lab-msp.com.  300  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clienta.example; ruf=mailto:dmarc@clienta.example; sp=reject; adkim=s; aspf=s"
clienta.paleon-lab-msp.com.         300  TXT  "v=spf1 ip4:<EIP> -all"
```

### Client B (Clean)
```
clientb._dmarc.paleon-lab-msp.com.  300  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clientb.example; ruf=mailto:dmarc@clientb.example; sp=reject; adkim=s; aspf=s"
clientb.paleon-lab-msp.com.         300  TXT  "v=spf1 ip4:<EIP> -all"
```

### Client C (Neglected - p=none)
```
clientc._dmarc.paleon-lab-msp.com.  300  TXT  "v=DMARC1; p=none; rua=mailto:dmarc@clientc.example"
clientc.paleon-lab-msp.com.         300  TXT  "v=spf1 ip4:<EIP> -all"
```

### Client D (Clean)
```
clientd._dmarc.paleon-lab-msp.com.  300  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@clientd.example; ruf=mailto:dmarc@clientd.example; sp=reject; adkim=s; aspf=s"
clientd.paleon-lab-msp.com.         300  TXT  "v=spf1 ip4:<EIP> -all"
```

### MSP Parent (Clean)
```
msp._dmarc.paleon-lab-msp.com.      300  TXT  "v=DMARC1; p=reject; rua=mailto:dmarc@msp.example; ruf=mailto:dmarc@msp.example; sp=reject; adkim=s; aspf=s"
msp.paleon-lab-msp.com.             300  TXT  "v=spf1 ip4:<EIP> -all"
```

## CAA Records (Optional)

```
paleon-lab-msp.com.  300  CAA  0 issue "letsencrypt.org"
paleon-lab-msp.com.  300  CAA  0 issuewild "letsencrypt.org"
paleon-lab-msp.com.  300  CAA  0 iodef "mailto:security@paleon.example"
```

## Verification

```bash
# Check clean hosts resolve to the clean EIP
for host in msp clienta clientb clientd; do
  dig +short $host.paleon-lab-msp.com
done

# Check Client C resolves to the Client C EIP
dig +short clientc.paleon-lab-msp.com

# Check DMARC records
for host in msp clienta clientb clientc clientd; do
  dig +short TXT ${host}._dmarc.paleon-lab-msp.com
done

# Check SPF records
for host in msp clienta clientb clientc clientd; do
  dig +short TXT ${host}.paleon-lab-msp.com
done
```

## Expected Scanner Observations

| Client | DMARC Policy | SPF | Expected Finding |
|--------|--------------|-----|------------------|
| MSP | p=reject | Strict (-all) | Clean |
| Client A | p=reject | Strict (-all) | Clean |
| Client B | p=reject | Strict (-all) | Clean |
| Client C | **p=none** | Strict (-all) | **DMARC p=none (Medium)** |
| Client D | p=reject | Strict (-all) | Clean |

## Notes

- All SPF records use the EIP for alignment
- DMARC `rua` addresses are fictional (example domains)
- No MX records (no actual email service)
- Scanner should only observe DNS records, not attempt email delivery