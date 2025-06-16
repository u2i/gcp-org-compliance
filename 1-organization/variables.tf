variable "org_id" {
  description = "Organization ID"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID"
  type        = string
}

variable "terraform_sa_email" {
  description = "Terraform service account email from bootstrap"
  type        = string
}

variable "project_prefix" {
  description = "Prefix for created projects"
  type        = string
  default     = "compliance"
}

variable "company_name" {
  description = "Company name to use in project naming (lowercase, no spaces)"
  type        = string
}

variable "security_email" {
  description = "Security contact email"
  type        = string
}

variable "compliance_email" {
  description = "Compliance contact email"
  type        = string
}

variable "allowed_domains" {
  description = "Allowed domains for IAM policies"
  type        = list(string)
}

variable "allowed_locations" {
  description = "Allowed GCP regions"
  type        = list(string)
  default     = [
    # US regions
    "us-central1", "us-east1", "us-east4", "us-east5", 
    "us-south1", "us-west1", "us-west2", "us-west3", "us-west4",
    # EU regions  
    "europe-central2", "europe-north1", "europe-southwest1", 
    "europe-west1", "europe-west2", "europe-west3", "europe-west4", 
    "europe-west6", "europe-west8", "europe-west9", "europe-west10", "europe-west12"
  ]
}

variable "developers_group" {
  description = "Google group for all developers"
  type        = string
}

variable "approvers_group" {
  description = "Google group for PAM approvers"
  type        = string
}

variable "tfstate_bucket" {
  description = "Terraform state bucket name"
  type        = string
  default     = "u2i-tfstate"
}