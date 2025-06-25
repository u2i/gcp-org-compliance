# Google Workspace Groups for GCP Break-Glass Policy v0.7
# These groups control GitHub permissions, GCP IAM bindings, and approval rights

locals {
  # Groups aligned with policy v0.7 section 3
  groups = {
    # Developer - Feature branches, read prod logs
    developers = "gcp-developers@${var.domain}"
    
    # Prod Support - Merge & deploy lane #1, on-call rotation
    prodsupport = "gcp-prodsupport@${var.domain}"
    
    # Tech Lead (AppSec-trained) - Approve lanes #1-4, acts as Security Reviewer
    techlead = "gcp-techlead@${var.domain}"
    
    # Tech Mgmt - Same as Tech Lead plus org-level sign-off (CEO/COO)
    techmgmt = "gcp-techmgmt@${var.domain}"
    
    # Billing/Finance - Read-only cost dashboards & invoice export
    billing = "gcp-billing@${var.domain}"
  }
  
  # Legacy groups for backward compatibility during migration
  legacy_groups = {
    admins    = "gcp-admins@${var.domain}"     # To be migrated to techmgmt
    approvers = "gcp-approvers@${var.domain}"  # To be migrated to prodsupport
    auditors  = "gcp-auditors@${var.domain}"   # To be migrated to billing
  }
}

# Data sources to verify groups exist in Google Workspace
# Note: These require the Workspace Admin SDK API to be enabled
# and the Terraform service account to have appropriate permissions

# Commented out as these require Workspace API access
# Uncomment after granting permissions to Terraform service account
/*
data "googleworkspace_group" "developers" {
  email = local.groups.developers
}

data "googleworkspace_group" "prodsupport" {
  email = local.groups.prodsupport
}

data "googleworkspace_group" "techlead" {
  email = local.groups.techlead
}

data "googleworkspace_group" "techmgmt" {
  email = local.groups.techmgmt
}

data "googleworkspace_group" "billing" {
  email = local.groups.billing
}
*/

# Outputs for use in other modules
output "groups" {
  description = "Map of group names to email addresses per policy v0.7"
  value       = local.groups
}

output "group_emails" {
  description = "List of all group email addresses"
  value = [
    local.groups.developers,
    local.groups.prodsupport,
    local.groups.techlead,
    local.groups.techmgmt,
    local.groups.billing
  ]
}

output "approval_groups" {
  description = "Groups that can approve various operations"
  value = {
    code_review     = [local.groups.prodsupport, local.groups.techlead, local.groups.techmgmt]
    security_review = [local.groups.techlead, local.groups.techmgmt]
    jit_lane1      = [local.groups.prodsupport, local.groups.techlead, local.groups.techmgmt]
    jit_lane2      = [local.groups.techlead, local.groups.techmgmt]
    jit_lane3      = [local.groups.techmgmt]
    jit_lane4      = [local.groups.techmgmt]
  }
}