# Simplified Variables for Belgium GKE Deployment

variable "billing_account" {
  description = "Billing account ID for GKE projects"
  type        = string
}

variable "tfstate_bucket" {
  description = "GCS bucket for Terraform state"
  type        = string
}

variable "primary_region" {
  description = "Primary region for GKE clusters (Belgium/EU deployment)"
  type        = string
  default     = "europe-west1"
}