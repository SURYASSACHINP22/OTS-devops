variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "OTS-DevOps"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_key_path" {
  description = "Path to the SSH public key"
  type        = string
  default     = "/home/newsu/.ssh/ots-devops.pub"
}

variable "root_volume_size" {
  description = "Root EBS volume size"

  type = number

  default = 15
}

variable "jenkins_admin_cidr" {
  description = "CIDR allowed to reach the Jenkins UI (port 8080). Defaults to the operator's current public IP -- update if it changes (e.g. dynamic home/mobile ISP)."
  type        = string
  default     = "47.11.42.250/32"
}