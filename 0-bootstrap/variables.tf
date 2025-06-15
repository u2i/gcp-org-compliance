variable "org_id" {
  description = "Organization ID"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID"
  type        = string
}

variable "project_prefix" {
  description = "Prefix for project IDs"
  type        = string
  default     = "org"
}

variable "bootstrap_project_id" {
  description = "Bootstrap project ID (created manually)"
  type        = string
}

variable "state_bucket" {
  description = "State bucket name (created manually)"
  type        = string
}