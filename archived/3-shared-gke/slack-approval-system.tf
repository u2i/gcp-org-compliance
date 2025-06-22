# Centralized Slack Approval System for Infrastructure Changes
# This provides organization-wide approval capabilities for all tenant projects

locals {
  approval_function_name = "u2i-slack-approval-handler"
  approval_bucket_name   = "u2i-terraform-approvals"
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "monitoring.googleapis.com",
    "logging.googleapis.com",
    "artifactregistry.googleapis.com"
  ])

  project = var.organization_project_id
  service = each.value
  
  disable_on_destroy = false
}

# Create Secret Manager service identity for CMEK
resource "google_project_service_identity" "secretmanager" {
  provider = google-beta
  service  = "secretmanager.googleapis.com"
  project  = var.organization_project_id
  
  depends_on = [google_project_service.required_apis]
}

# KMS resources for bucket encryption
resource "google_kms_key_ring" "approval_keyring" {
  name     = "approval-system-keyring"
  location = var.primary_region
  project  = var.organization_project_id
}

resource "google_kms_crypto_key" "approval_bucket_key" {
  name     = "approval-bucket-key"
  key_ring = google_kms_key_ring.approval_keyring.id
  purpose  = "ENCRYPT_DECRYPT"
  
  labels = {
    purpose        = "infrastructure-approvals"
    compliance     = "iso27001-soc2-gdpr"
    data_residency = "eu"
  }
  
  depends_on = [google_project_service.required_apis]
}

# Grant service accounts access to KMS key for encryption
resource "google_kms_crypto_key_iam_member" "storage_service_encryption" {
  crypto_key_id = google_kms_crypto_key.approval_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "secretmanager_service_encryption" {
  crypto_key_id = google_kms_crypto_key.approval_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

resource "google_kms_crypto_key_iam_member" "artifactregistry_service_encryption" {
  crypto_key_id = google_kms_crypto_key.approval_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-artifactregistry.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "cloudfunctions_service_encryption" {
  crypto_key_id = google_kms_crypto_key.approval_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@gcf-admin-robot.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "cloudrun_service_encryption" {
  crypto_key_id = google_kms_crypto_key.approval_bucket_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@serverless-robot-prod.iam.gserviceaccount.com"
}

data "google_project" "current" {
  project_id = var.organization_project_id
}

# Artifact Registry repository for Cloud Functions with CMEK
resource "google_artifact_registry_repository" "function_repo" {
  repository_id = "cloud-functions"
  location      = var.primary_region
  format        = "DOCKER"
  project       = var.organization_project_id
  
  kms_key_name = google_kms_crypto_key.approval_bucket_key.id
  
  labels = {
    purpose     = "cloud-functions"
    compliance  = "iso27001-soc2-gdpr"
    environment = "production"
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_member.artifactregistry_service_encryption
  ]
}

# Storage bucket for approval decisions
resource "google_storage_bucket" "approval_storage" {
  name                        = local.approval_bucket_name
  location                    = var.primary_region
  project                     = var.organization_project_id
  uniform_bucket_level_access = true
  force_destroy               = false
  
  encryption {
    default_kms_key_name = google_kms_crypto_key.approval_bucket_key.id
  }
  
  depends_on = [google_kms_crypto_key_iam_member.storage_service_encryption]

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
  name                        = "${local.approval_function_name}-source"
  location                    = var.primary_region
  project                     = var.organization_project_id
  uniform_bucket_level_access = true

  labels = {
    purpose = "cloud-function-source"
  }
  
  encryption {
    default_kms_key_name = google_kms_crypto_key.approval_bucket_key.id
  }
  
  depends_on = [google_kms_crypto_key_iam_member.storage_service_encryption]
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
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.approval_bucket_key.id
        }
      }
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_member.secretmanager_service_encryption
  ]
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
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.approval_bucket_key.id
        }
      }
    }
  }
  
  depends_on = [
    google_project_service.required_apis,
    google_kms_crypto_key_iam_member.secretmanager_service_encryption
  ]
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
    runtime           = "nodejs18"
    entry_point       = "handleSlackInteraction"
    docker_repository = google_artifact_registry_repository.function_repo.id
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

    ingress_settings = "ALLOW_ALL"
  }

  labels = {
    environment = "production"
    purpose     = "infrastructure-approvals"
    compliance  = "iso27001-soc2-gdpr"
  }

  kms_key_name = google_kms_crypto_key.approval_bucket_key.id
  
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

# Cloud Functions v2 uses Cloud Run, so we need to add IAM binding for the underlying service
resource "google_cloud_run_service_iam_member" "approval_function_invoker_run" {
  project  = var.organization_project_id
  location = google_cloudfunctions2_function.approval_handler.location
  service  = google_cloudfunctions2_function.approval_handler.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Monitoring dashboard removed to simplify deployment
# Can be added later once the core approval system is working

# Outputs are defined in outputs.tf to avoid duplication