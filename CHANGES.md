# Changes — Paleon Test Site 5

## [Unreleased] - 2026-09-04

### Added
- Complete repository structure for MSP multi-client estate
- Terraform infrastructure (EC2, EIP, Route53, Security Group, S3 backend)
- Nginx HTTP bootstrap and HTTPS final configurations
- Website content for MSP parent and 4 clients
- Client A: Clean with ARN false-positive trap
- Client B: Subtle (expiring cert, one missing header)
- Client C: Neglected (expired cert, missing HSTS/CSP, DMARC p=none, exposed .git, open port 5432)
- Client D: Clean control
- DNS polling script with exact EIP verification
- Certificate setup script (Let's Encrypt + self-signed for test scenarios)
- Dummy PostgreSQL listener on port 5432
- Self-contained user-data bootstrap
- Expected.yaml with all scanner expectations
- Validation script (validate.sh)
- Reset script (reset.sh)
- Verification script (verify.sh)
- Documentation: README, ARCHITECTURE, DEPLOYMENT, CHANGES
- Supporting docs: DNS records, TLS architecture, port map

### Security
- IMDSv2 enforced on EC2
- SSH restricted to admin_ip_cidr
- No real credentials in repository
- S3 state backend with encryption and versioning
- Dummy database listener (no real database)

---

## Version Format

This project uses a simplified versioning aligned with the test site number:
- **Site 5** = This implementation

Future sites would increment the site number.