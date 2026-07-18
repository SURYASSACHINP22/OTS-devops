resource "aws_security_group" "ec2_sg" {
  name        = "ots-devops-ec2-sg"
  description = "Security group for OTS DevOps EC2"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"

    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"

    from_port = 80
    to_port   = 80
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"

    from_port = 443
    to_port   = 443
    protocol  = "tcp"

    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Jenkins UI (admin only)"

    from_port = 8080
    to_port   = 8080
    protocol  = "tcp"

    cidr_blocks = [var.jenkins_admin_cidr]
  }

  ingress {
    description = "Grafana UI via NodePort (admin only)"

    from_port = 31123
    to_port   = 31123
    protocol  = "tcp"

    # Reuses the same operator-IP variable as Jenkins -- this was
    # previously a manual, untracked SG rule added outside Terraform.
    # Bringing it into IaC here so it isn't silently lost/drifted.
    cidr_blocks = [var.jenkins_admin_cidr]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "ots-devops-ec2-sg"
    }
  )
}