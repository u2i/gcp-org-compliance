variable "terraform_state_bucket" {
  description = "GCS bucket for Terraform state"
  type        = string
}

variable "org_id" {
  description = "GCP Organization ID"
  type        = string
}

variable "org_prefix" {
  description = "Organization prefix for resource naming"
  type        = string
  default     = "u2i"
}

variable "domain" {
  description = "Organization domain"
  type        = string
  default     = "u2i.com"
}

variable "billing_account" {
  description = "Billing account ID"
  type        = string
}

variable "primary_region" {
  description = "Primary region for resources"
  type        = string
  default     = "europe-west1"
}

variable "failsafe_account" {
  description = "Failsafe account email"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for security alerts"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pagerduty_service_key" {
  description = "PagerDuty service key for on-call alerts"
  type        = string
  sensitive   = true
  default     = ""
}