variable "primary_region" {
  description = "Primary region for resources"
  type        = string
  default     = "europe-west1"
}

variable "organization_project_id" {
  description = "GCP project ID for organization-level resources"
  type        = string
  default     = "u2i-gke-nonprod" # Using existing shared project
}

variable "github_approval_token" {
  description = "GitHub personal access token for triggering approval workflows"
  type        = string
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Slack app signing secret for verifying webhook requests"
  type        = string
  sensitive   = true
}