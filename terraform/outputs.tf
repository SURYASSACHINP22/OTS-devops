output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devops_server.id
}

output "public_ip" {
  description = "EC2 instance public IP address (Elastic IP -- stable across stop/resize)"
  value       = aws_eip.devops_server.public_ip
}

output "private_ip" {
  description = "EC2 instance private IP address"
  value       = aws_instance.devops_server.private_ip
}

output "ssh_command" {
  description = "Convenience command to SSH into the instance"
  value       = "ssh -i ~/.ssh/ots-devops ubuntu@${aws_eip.devops_server.public_ip}"
}

output "nip_io_domain" {
  description = "Free wildcard-DNS domain that resolves to the Elastic IP, for Ingress/TLS"
  value       = "${aws_eip.devops_server.public_ip}.nip.io"
}
