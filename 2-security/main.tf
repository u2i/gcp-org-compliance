# Security Phase - Organization Security and Compliance Infrastructure
# This module sets up centralized security services including PAM, logging, and monitoring

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
  }
}

# Reference organization outputs
data "terraform_remote_state" "organization" {
  backend = "gcs"
  config = {
    bucket = var.terraform_state_bucket
    prefix = "organization"
  }
}

locals {
  # Use values from terraform.tfvars since organization outputs don't include these
  org_id              = var.org_id
  # Create folders directly since they're not in the organization outputs
  security_folder_id  = google_folder.security.id
  production_folder   = google_folder.production.id
  nonproduction_folder = google_folder.nonproduction.id
}

# Create the necessary folders
resource "google_folder" "security" {
  display_name = "Security"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "production" {
  display_name = "Production"
  parent       = "organizations/${var.org_id}"
}

resource "google_folder" "nonproduction" {
  display_name = "Non-Production"
  parent       = "organizations/${var.org_id}"
}

# Security project for centralized security services
resource "google_project" "security" {
  name            = "Security Operations"
  project_id      = "${var.org_prefix}-security"
  folder_id       = local.security_folder_id
  billing_account = var.billing_account

  labels = {
    environment = "security"
    purpose     = "security-operations"
    compliance  = "iso27001-soc2-gdpr"
  }
}

# Logging project for centralized audit logs
resource "google_project" "logging" {
  name            = "Centralized Logging"
  project_id      = "${var.org_prefix}-logging"
  folder_id       = local.security_folder_id
  billing_account = var.billing_account

  labels = {
    environment = "security"
    purpose     = "audit-logging"
    compliance  = "iso27001-soc2-gdpr"
  }
}

# Enable required APIs
resource "google_project_service" "security_apis" {
  for_each = toset([
    "privilegedaccessmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "bigquery.googleapis.com",
    "cloudasset.googleapis.com",
    "securitycenter.googleapis.com",
    "cloudkms.googleapis.com"
  ])

  project = google_project.security.project_id
  service = each.key

  disable_on_destroy = false
}

resource "google_project_service" "logging_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "logging.googleapis.com",
    "storage.googleapis.com"
  ])

  project = google_project.logging.project_id
  service = each.key

  disable_on_destroy = false
}

# BigQuery dataset for audit logs
resource "google_bigquery_dataset" "audit_logs" {
  project    = google_project.logging.project_id
  dataset_id = "audit_logs"
  location   = var.primary_region

  description = "Centralized audit logs for compliance and security monitoring"

  default_table_expiration_ms = 7776000000  # 90 days
  
  default_encryption_configuration {
    kms_key_name = google_kms_crypto_key.audit_logs_key.id
  }

  access {
    role          = "OWNER"
    user_by_email = var.failsafe_account
  }

  access {
    role          = "READER"
    group_by_email = "gcp-security-analysts@${var.domain}"
  }

  labels = {
    compliance     = "iso27001-soc2-gdpr"
    data_residency = "eu"
    purpose        = "audit-logs"
  }
}

# KMS keyring for security resources
resource "google_kms_key_ring" "security" {
  project  = google_project.security.project_id
  name     = "security-keyring"
  location = var.primary_region
}

# KMS key for audit logs encryption
resource "google_kms_crypto_key" "audit_logs_key" {
  name     = "audit-logs-key"
  key_ring = google_kms_key_ring.security.id
  purpose  = "ENCRYPT_DECRYPT"

  rotation_period = "7776000s"  # 90 days

  lifecycle {
    prevent_destroy = true
  }
}

# Service account for GitHub Actions CI/CD
resource "google_service_account" "github_actions" {
  project      = google_project.security.project_id
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
  description  = "Service account for GitHub Actions automation with PAM elevation"
}

# Notification channels for security alerts
resource "google_monitoring_notification_channel" "security_email" {
  project      = google_project.security.project_id
  display_name = "Security Team Email"
  type         = "email"
  
  labels = {
    email_address = "security@${var.domain}"
  }
}

resource "google_monitoring_notification_channel" "security_slack" {
  count        = var.slack_webhook_url != "" ? 1 : 0
  project      = google_project.security.project_id
  display_name = "Security Alerts Slack"
  type         = "slack"
  
  labels = {
    channel_name = "#security-alerts"
  }
  
  user_labels = {
    webhook_url = var.slack_webhook_url
  }
}

resource "google_monitoring_notification_channel" "oncall_pagerduty" {
  count        = var.pagerduty_service_key != "" ? 1 : 0
  project      = google_project.security.project_id
  display_name = "On-Call PagerDuty"
  type         = "pagerduty"
  
  user_labels = {
    service_key = var.pagerduty_service_key
  }
}