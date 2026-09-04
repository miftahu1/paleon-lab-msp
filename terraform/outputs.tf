# Terraform Outputs
# Site 5 - MSP Multi-Client Estate

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.msp.id
}

output "instance_public_ip" {
  description = "EC2 Instance public IP (before EIP association)"
  value       = aws_instance.msp.public_ip
}

output "eip_public_ip" {
  description = "Elastic IP address"
  value       = aws_eip.msp.public_ip
}

output "eip_allocation_id" {
  description = "Elastic IP allocation ID"
  value       = aws_eip.msp.id
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.msp.id
}

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = aws_route53_zone.msp.zone_id
}

output "route53_zone_name" {
  description = "Route53 Hosted Zone Name"
  value       = aws_route53_zone.msp.name
}

output "route53_name_servers" {
  description = "Route53 Name Servers"
  value       = aws_route53_zone.msp.name_servers
}

output "hostnames" {
  description = "Map of hostname to FQDN"
  value = {
    msp     = "msp.${var.domain_name}"
    clienta = "clienta.${var.domain_name}"
    clientb = "clientb.${var.domain_name}"
    clientc = "clientc.${var.domain_name}"
    clientd = "clientd.${var.domain_name}"
  }
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.msp.public_ip}"
}

output "expected_ip_file" {
  description = "Path to expected IP file on instance"
  value       = "/etc/expected_ip"
}

output "website_root" {
  description = "Website document root on instance"
  value       = "/var/www"
}

output "nginx_config_dir" {
  description = "Nginx config directory on instance"
  value       = "/etc/nginx/sites-available"
}

output "ssl_cert_dir" {
  description = "SSL certificate directory on instance"
  value       = "/etc/ssl/certs"
}

output "letsencrypt_dir" {
  description = "Let's Encrypt certificate directory on instance"
  value       = "/etc/letsencrypt/live"
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    instance_id    = aws_instance.msp.id
    instance_type  = var.instance_type
    eip            = aws_eip.msp.public_ip
    domain         = var.domain_name
    hostnames      = ["msp", "clienta", "clientb", "clientc", "clientd"]
    open_ports     = [80, 443, 5432]
    ssh_restricted = var.admin_ip_cidr
    security_group = aws_security_group.msp.id
    route53_zone   = aws_route53_zone.msp.zone_id
  }
}