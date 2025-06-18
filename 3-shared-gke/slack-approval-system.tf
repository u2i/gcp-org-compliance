# Centralized Slack Approval System for Infrastructure Changes
# This provides organization-wide approval capabilities for all tenant projects

locals {
  approval_function_name = "u2i-slack-approval-handler"
  approval_bucket_name   = "u2i-terraform-approvals"
}

# Storage bucket for approval decisions
resource "google_storage_bucket" "approval_storage" {
  name                        = local.approval_bucket_name
  location                    = var.primary_region
  project                     = var.organization_project_id
  uniform_bucket_level_access = true
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90 # Keep approval records for 90 days for audit
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    environment    = "production"
    purpose        = "infrastructure-approvals"
    compliance     = "iso27001-soc2-gdpr"
    data_residency = "eu"
  }
}

# IAM for approval bucket - allow tenant service accounts to read/write approvals
resource "google_storage_bucket_iam_member" "tenant_approval_access" {
  for_each = toset([
    "serviceAccount:terraform@u2i-tenant-webapp.iam.gserviceaccount.com",
    # Add other tenant service accounts as they're created
  ])

  bucket = google_storage_bucket.approval_storage.name
  role   = "roles/storage.objectAdmin"
  member = each.value
}

# Cloud Function source code
resource "google_storage_bucket" "function_source" {
  name     = "${local.approval_function_name}-source"
  location = var.primary_region
  project  = var.organization_project_id

  labels = {
    purpose = "cloud-function-source"
  }
}

# Package and upload function source
data "archive_file" "approval_function_source" {
  type        = "zip"
  output_path = "/tmp/slack-approval-handler.zip"
  source_dir  = "${path.module}/slack-approval-handler"
}

resource "google_storage_bucket_object" "approval_function_source" {
  name   = "slack-approval-handler-${data.archive_file.approval_function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.approval_function_source.output_path
}

# Service account for the approval function
resource "google_service_account" "approval_function_sa" {
  account_id   = "slack-approval-handler"
  display_name = "Slack Approval Handler Service Account"
  description  = "Service account for centralized Slack approval system"
  project      = var.organization_project_id
}

# Grant function service account permissions
resource "google_project_iam_member" "approval_function_permissions" {
  for_each = toset([
    "roles/storage.objectAdmin",    # Access approval bucket
    "roles/logging.logWriter",      # Write audit logs
    "roles/monitoring.metricWriter" # Write metrics
  ])

  project = var.organization_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.approval_function_sa.email}"
}

# Allow function to trigger workflows in tenant repositories
resource "google_secret_manager_secret" "github_token" {
  secret_id = "github-approval-token"
  project   = var.organization_project_id

  labels = {
    purpose = "github-integration"
  }

  replication {
    user_managed {
      replicas {
        location = var.primary_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "github_token" {
  secret      = google_secret_manager_secret.github_token.id
  secret_data = var.github_approval_token # Set via terraform.tfvars or environment
}

resource "google_secret_manager_secret" "slack_signing_secret" {
  secret_id = "slack-signing-secret"
  project   = var.organization_project_id

  labels = {
    purpose = "slack-integration"
  }

  replication {
    user_managed {
      replicas {
        location = var.primary_region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "slack_signing_secret" {
  secret      = google_secret_manager_secret.slack_signing_secret.id
  secret_data = var.slack_signing_secret # Set via terraform.tfvars or environment
}

# Grant function access to secrets
resource "google_secret_manager_secret_iam_member" "github_token_access" {
  secret_id = google_secret_manager_secret.github_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.approval_function_sa.email}"
  project   = var.organization_project_id
}

resource "google_secret_manager_secret_iam_member" "slack_secret_access" {
  secret_id = google_secret_manager_secret.slack_signing_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.approval_function_sa.email}"
  project   = var.organization_project_id
}

# Cloud Function for Slack approval handling
resource "google_cloudfunctions2_function" "approval_handler" {
  name        = local.approval_function_name
  location    = var.primary_region
  description = "Centralized Slack approval handler for U2I infrastructure changes"
  project     = var.organization_project_id

  build_config {
    runtime     = "nodejs18"
    entry_point = "handleSlackInteraction"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.approval_function_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.approval_function_sa.email

    environment_variables = {
      APPROVAL_BUCKET         = google_storage_bucket.approval_storage.name
      GCP_PROJECT            = var.organization_project_id
      GITHUB_TOKEN_SECRET    = google_secret_manager_secret.github_token.secret_id
      SLACK_SIGNING_SECRET   = google_secret_manager_secret.slack_signing_secret.secret_id
    }

    ingress = "INGRESS_SETTINGS_ALLOW_ALL"
  }

  labels = {
    environment = "production"
    purpose     = "infrastructure-approvals"
    compliance  = "iso27001-soc2-gdpr"
  }

  depends_on = [
    google_storage_bucket_object.approval_function_source,
    google_service_account.approval_function_sa,
    google_secret_manager_secret_version.github_token,
    google_secret_manager_secret_version.slack_signing_secret
  ]
}

# Make the function publicly accessible (with Slack signature verification for security)
resource "google_cloudfunctions2_function_iam_member" "approval_function_invoker" {
  project        = var.organization_project_id
  location       = google_cloudfunctions2_function.approval_handler.location
  cloud_function = google_cloudfunctions2_function.approval_handler.name
  role           = "roles/cloudfunctions.invoker"
  member         = "allUsers"
}

# Create monitoring dashboard for approval metrics
resource "google_monitoring_dashboard" "approval_metrics" {
  dashboard_json = jsonencode({
    displayName = "Infrastructure Approval Metrics"
    mosaicLayout = {
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Approval Requests"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type=\"cloud_function\" AND resource.labels.function_name=\"${local.approval_function_name}\""
                    aggregation = {
                      alignmentPeriod  = "60s"
                      perSeriesAligner = "ALIGN_RATE"
                    }
                  }
                }
              }]
            }
          }
        }
      ]
    }
  })
  project = var.organization_project_id
}

# Outputs for tenant projects to use
output "approval_system" {
  description = "Centralized approval system configuration"
  value = {
    function_url    = google_cloudfunctions2_function.approval_handler.service_config[0].uri
    approval_bucket = google_storage_bucket.approval_storage.name
    
    # For tenant workflows to reference
    slack_button_values = {
      webapp_team = "approve:webapp-team-infrastructure:{run_id}"
      data_team   = "approve:data-team-infrastructure:{run_id}" 
      org_level   = "approve:gcp-org-compliance:{run_id}"
    }
    
    # Instructions for Slack app configuration
    slack_configuration = {
      interactive_components_url = google_cloudfunctions2_function.approval_handler.service_config[0].uri
      required_scopes = [
        "chat:write",
        "commands",
        "users:read"
      ]
    }
  }
}