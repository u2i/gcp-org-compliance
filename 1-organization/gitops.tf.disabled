# GitOps Infrastructure - Workload Identity Federation and GitHub Actions Setup

# Get bootstrap project data
data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  config = {
    bucket = var.tfstate_bucket
    prefix = "bootstrap"
  }
}

# Create Workload Identity Pool for GitHub Actions
resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = data.terraform_remote_state.bootstrap.outputs.bootstrap_project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions Pool"
  description               = "Identity pool for GitHub Actions GitOps workflows"
}

# Create GitHub provider for the pool
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = data.terraform_remote_state.bootstrap.outputs.bootstrap_project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub Provider"
  description                        = "GitHub OIDC provider for GitOps"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Create service accounts for different environments
resource "google_service_account" "terraform_organization" {
  account_id   = "terraform-organization"
  display_name = "Terraform Organization SA (Zero Standing Privilege)"
  description  = "Organization-wide Terraform deployments - read-only + PAM elevation"
  project      = data.terraform_remote_state.bootstrap.outputs.bootstrap_project_id
}

resource "google_service_account" "terraform_security" {
  account_id   = "terraform-security"
  display_name = "Terraform Security SA (Zero Standing Privilege)" 
  description  = "Security project deployments - read-only + PAM elevation"
  project      = data.terraform_remote_state.bootstrap.outputs.bootstrap_project_id
}

# Grant baseline read-only permissions to organization SA
resource "google_organization_iam_member" "terraform_org_baseline" {
  for_each = toset([
    "roles/viewer",
    "roles/iam.securityReviewer", 
    "roles/resourcemanager.folderViewer",
    "roles/orgpolicy.policyViewer",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/billing.viewer",
    "roles/securitycenter.settingsViewer",
  ])
  
  org_id = var.org_id
  role   = each.key
  member = "serviceAccount:${google_service_account.terraform_organization.email}"
}

# Grant state bucket access to organization SA
resource "google_storage_bucket_iam_member" "terraform_org_state" {
  bucket = data.terraform_remote_state.bootstrap.outputs.tfstate_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_organization.email}"
  
  condition {
    title      = "Only organization state"
    expression = "resource.name.startsWith('${data.terraform_remote_state.bootstrap.outputs.tfstate_bucket}/organization/')"
  }
}

# Grant state bucket access to security SA
resource "google_storage_bucket_iam_member" "terraform_security_state" {
  bucket = data.terraform_remote_state.bootstrap.outputs.tfstate_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.terraform_security.email}"
  
  condition {
    title      = "Only security state"
    expression = "resource.name.startsWith('${data.terraform_remote_state.bootstrap.outputs.tfstate_bucket}/security/')"
  }
}

# Allow GitHub Actions to impersonate service accounts
resource "google_service_account_iam_member" "github_terraform_org" {
  service_account_id = google_service_account.terraform_organization.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/u2i/gcp-org-compliance"
}

resource "google_service_account_iam_member" "github_terraform_security" {
  service_account_id = google_service_account.terraform_security.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/u2i/gcp-org-compliance"
}

# Allow GitHub Actions to impersonate bootstrap SA for state migration
resource "google_service_account_iam_member" "github_terraform_bootstrap" {
  service_account_id = "projects/${data.terraform_remote_state.bootstrap.outputs.bootstrap_project_id}/serviceAccounts/${data.terraform_remote_state.bootstrap.outputs.terraform_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_actions.name}/attribute.repository/u2i/gcp-org-compliance"
}

# Note: Write permissions will be granted via PAM entitlements
# This ensures zero-standing-privilege model where SAs have read-only access
# and write operations require just-in-time elevation