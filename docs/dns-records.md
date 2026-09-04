# DNS Records — Paleon Test Site 5

## Hosted Zone

- **Domain**: `paleon-lab-msp.com`
- **Managed by**: Terraform (`aws_route53_zone`)
- **Delegation**: Not registered (test domain)

## A Records

All records point to the single Elastic IP (EIP) attached to the EC2 instance.

| Record Name | FQDN | Type | Value | TTL |
|-------------|------|------|-------|-----|
| msp | msp.paleon-lab-msp.com | A | EIP | 300 |
| clienta | clienta.paleon-lab-msp.com | A | EIP | 300 |
| clientb | clientb.paleon-lab-msp.com | A | EIP | 300 |
| clientc | clientc.paleon-lab-msp.com | A | EIP | 300 |
| clientd | clientd.paleon-lab-msp.com | A | EIP | 300 |

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

## DNSSEC

**Not enabled** for this test site.

If enabling in future:
1. Create KMS key for DNSSEC
2. Enable DNSSEC on hosted zone (`aws_route53_zone` with `dnssec_config`)
3. Publish DS records at registrar
4. Update `expected.yaml` with DNSSEC findings

## Verification

```bash
# Check all A records resolve to same IP
for host in msp clienta clientb clientc clientd; do
  dig +short $host.paleon-lab-msp.com
done

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