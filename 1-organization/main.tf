terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
  }
}

provider "google" {
  # Using failsafe account directly for initial setup
  # Will switch to service account impersonation after setup
  # impersonate_service_account = var.terraform_sa_email
}

# Create folder structure for gradual migration
module "org_structure" {
  source = "github.com/u2i/terraform-google-compliance-modules//modules/organization-structure?ref=v1.0.19"
  
  org_id = var.org_id
  
  folder_structure = {
    # Existing projects go here initially
    "legacy-systems" = {
      subfolders = ["external-apps", "internal-tools", "experiments"]
    }
    # Projects being migrated
    "migration-in-progress" = {
      subfolders = ["phase-1", "phase-2", "phase-3"]
    }
    # Fully compliant projects
    "compliant-systems" = {
      subfolders = ["production", "staging", "development", "shared-services"]
    }
  }
  
  essential_contacts = {
    security = {
      email                   = var.security_email
      notification_categories = ["SECURITY", "TECHNICAL"]
    }
    compliance = {
      email                   = var.compliance_email
      notification_categories = ["ALL"]
    }
  }
}

# Security policies with exceptions for legacy
module "security_baseline" {
  source = "github.com/u2i/terraform-google-compliance-modules//modules/security-baseline?ref=v1.0.19"
  
  parent_id  = var.org_id
  policy_for = "organization"
  
  # Enforce critical policies immediately
  enforce_policies = {
    # Security critical - enforce now
    disable_audit_logging_exemption = true
    uniform_bucket_level_access     = true
    public_access_prevention        = true
    require_ssl_sql                 = true
    restrict_public_sql             = true
    disable_project_deletion        = true
    
    # Enforce with exceptions for legacy
    disable_sa_key_creation      = true
    require_shielded_vm          = true
    disable_serial_port_access   = true
    skip_default_network         = true
    vm_external_ip_access        = true
    require_cmek_encryption      = true
    
    # Enable gradually
    require_os_login             = false  # Requires OS Login setup
    gke_enable_autopilot        = false  # For existing GKE clusters
    binary_authorization        = false  # Requires Binary Auth setup
  }
  
  allowed_domains   = var.allowed_domains
  allowed_locations = var.allowed_locations
  
  # Legacy folder gets exceptions
  policy_exceptions = {
    folders = {
      (module.org_structure.folder_ids["legacy-systems"]) = [
        "disable_sa_key_creation",
        "require_shielded_vm",
        "skip_default_network",
        "vm_external_ip_access",
        "require_cmek_encryption"
      ]
      # Partial exceptions for migration folder
      (module.org_structure.folder_ids["migration-in-progress"]) = [
        "disable_sa_key_creation",
        "vm_external_ip_access"
      ]
    }
  }
}

# Audit logging setup
module "audit_logging" {
  source = "github.com/u2i/terraform-google-compliance-modules//modules/audit-logging?ref=v1.0.19"
  
  org_id          = var.org_id
  billing_account = var.billing_account
  company_name    = var.company_name
  
  create_logging_project = true
  logging_project_name   = "${var.project_prefix}-security-logs"
  
  log_sinks = {
    # Immediate compliance requirement
    audit_logs = {
      destination_type = "logging_bucket"
      retention_days   = 365  # Increase to 2555 for full compliance
      location        = "us"
    }
    
    # Security monitoring
    security_events = {
      destination_type        = "bigquery"
      retention_days         = 90
      enable_real_time_alerts = true
      filter = <<-EOT
        severity >= "WARNING"
        AND (
          protoPayload.methodName:"SetIamPolicy"
          OR protoPayload.methodName:"Delete"
          OR resource.type:"project"
        )
      EOT
    }
  }
  
  enable_cmek = false  # Enable after KMS setup
}

# Configure group permissions (simplified for small org)
# Developers group - organization-wide read access
resource "google_organization_iam_member" "developers_org_permissions" {
  for_each = toset([
    "roles/viewer",
    "roles/iam.securityReviewer",
    "roles/logging.viewer",
    "roles/monitoring.viewer",
    "roles/billing.viewer",
  ])
  
  org_id = var.org_id
  role   = each.key
  member = "group:${var.developers_group}"
}

# Developers can edit in non-production folders
resource "google_folder_iam_member" "developers_folder_permissions" {
  for_each = {
    "legacy-edit"    = { folder = module.org_structure.folder_ids["legacy-systems"], role = "roles/editor" }
    "migration-edit" = { folder = module.org_structure.folder_ids["migration-in-progress"], role = "roles/editor" }
    "compliant-view" = { folder = module.org_structure.folder_ids["compliant-systems"], role = "roles/viewer" }
  }
  
  folder = each.value.folder
  role   = each.value.role
  member = "group:${var.developers_group}"
}

# Note: Approvers group permissions are configured in PAM module
# They inherit all developer permissions plus PAM approval rights