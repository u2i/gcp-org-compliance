# Organization-level Groups Configuration
# Defines the simplified groups structure for the entire organization

locals {
  # Core groups following simplified structure
  org_groups = {
    admins     = "gcp-admins@${var.domain}"
    approvers  = "gcp-approvers@${var.domain}"
    developers = "gcp-developers@${var.domain}"
    auditors   = "gcp-auditors@${var.domain}"
  }
}

# Grant organization-wide view permissions to developers
# This allows them to see projects and resources across the org
resource "google_organization_iam_member" "developers_org_viewer" {
  org_id = var.org_id
  role   = "roles/viewer"
  member = "group:${local.org_groups.developers}"
}

# Grant organization-wide billing viewer to auditors
# Only if audit access is enabled
resource "google_organization_iam_member" "auditors_billing_viewer" {
  count = var.enable_audit_access ? 1 : 0
  
  org_id = var.org_id
  role   = "roles/billing.viewer"
  member = "group:${local.org_groups.auditors}"
}

# Output for other modules to reference
output "organization_groups" {
  value = local.org_groups
  description = "Organization-wide Google groups"
}