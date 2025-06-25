terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
  
  backend "gcs" {
    bucket = "u2i-tfstate"
    prefix = "bootstrap"
  }
}

provider "google" {
  # Uses Application Default Credentials from failsafe account
}

# Import the manually created bootstrap project
resource "google_project" "bootstrap" {
  name            = "Organization Bootstrap"
  project_id      = var.bootstrap_project_id  # From terraform.tfvars
  org_id          = var.org_id
  billing_account = var.billing_account
  
  labels = {
    purpose         = "terraform-admin"
    managed_by      = "terraform"
    compliance      = "required"
    environment     = "bootstrap"
  }
  
  # Prevent accidental deletion
  deletion_policy = "PREVENT"
}

# Import already enabled APIs
resource "google_project_service" "bootstrap_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "storage.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudasset.googleapis.com",
    "logging.googleapis.com",
    "pubsub.googleapis.com",
    "monitoring.googleapis.com",
    "securitycenter.googleapis.com",
  ])
  
  project = google_project.bootstrap.project_id
  service = each.key
  
  disable_on_destroy = false
}

# Create Terraform service accounts following zero-standing-privilege model
# One service account per environment
resource "google_service_account" "terraform_bootstrap" {
  account_id   = "terraform-bootstrap"
  display_name = "Terraform Bootstrap SA (Zero Standing Privilege)"
  description  = "Bootstrap environment - read-only + state access only"
  project      = google_project.bootstrap.project_id
}

# Grant READ-ONLY baseline permissions
resource "google_organization_iam_member" "terraform_baseline_perms" {
  for_each = toset([
    "roles/viewer",                          # Read all resources
    "roles/iam.securityReviewer",           # Review IAM policies
    "roles/resourcemanager.folderViewer",   # View folder structure
    "roles/orgpolicy.policyViewer",         # View org policies
    "roles/logging.viewer",                 # View logs
    "roles/monitoring.viewer",              # View metrics
    "roles/billing.viewer",                 # View billing
    "roles/securitycenter.settingsViewer",  # View SCC settings
  ])
  
  org_id = var.org_id
  role   = each.key
  member = "serviceAccount:${google_service_account.terraform_bootstrap.email}"
}

# Note: Write permissions will be granted via PAM just-in-time elevation
# See DETAILED_ARCHITECTURE.md for PAM configuration

# Import the manually created state bucket
resource "google_storage_bucket" "tfstate" {
  name     = var.state_bucket  # From terraform.tfvars
  location = "US"
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 30
      with_state         = "ARCHIVED"
    }
  }
}

# Grant Terraform SA access to state bucket - only for its environment
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_bootstrap.email}"
  
  condition {
    title      = "Only bootstrap state"
    expression = "resource.name.startsWith('${google_storage_bucket.tfstate.name}/bootstrap/')"
  }
}