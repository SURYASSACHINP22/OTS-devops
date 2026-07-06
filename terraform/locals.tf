locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "OTS-DevOps"
    Owner       = "Sachin Suryawanshi"
  }
}
