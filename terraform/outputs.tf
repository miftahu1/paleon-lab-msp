// Terraform Outputs
// Site 5 - MSP Multi-Client Estate

output "clean_instance_id" {
  description = "EC2 Instance ID for clean instance"
  value       = aws_instance.clean.id
}

output "clientc_instance_id" {
  description = "EC2 Instance ID for Client C instance"
  value       = aws_instance.clientc.id
}

output "clean_eip_public_ip" {
  description = "Public IP for clean Elastic IP"
  value       = aws_eip.clean.public_ip
}

output "clientc_eip_public_ip" {
  description = "Public IP for clientc Elastic IP"
  value       = aws_eip.clientc.public_ip
}

output "clean_eip_allocation_id" {
  description = "Allocation ID for clean EIP"
  value       = aws_eip.clean.id
}

output "clientc_eip_allocation_id" {
  description = "Allocation ID for clientc EIP"
  value       = aws_eip.clientc.id
}

output "clean_security_group_id" {
  description = "Security Group ID for clean instance"
  value       = aws_security_group.clean.id
}

output "clientc_security_group_id" {
  description = "Security Group ID for clientc instance"
  value       = aws_security_group.clientc.id
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

output "ssh_command_clean" {
  description = "SSH command to connect to clean instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.clean.public_ip}"
}

output "ssh_command_clientc" {
  description = "SSH command to connect to clientc instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.clientc.public_ip}"
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
    clean_instance_id      = aws_instance.clean.id
    clientc_instance_id    = aws_instance.clientc.id
    instance_type          = var.instance_type
    clean_eip              = aws_eip.clean.public_ip
    clientc_eip            = aws_eip.clientc.public_ip
    domain                 = var.domain_name
    hostnames              = ["msp", "clienta", "clientb", "clientc", "clientd"]
    open_ports             = [80, 443, 5432]
    ssh_restricted         = var.admin_ip_cidr
    clean_security_group   = aws_security_group.clean.id
    clientc_security_group = aws_security_group.clientc.id
    route53_zone           = aws_route53_zone.msp.zone_id
  }
}