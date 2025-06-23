# Organization-Level PAM and Break Glass Configuration
# This implements zero-standing-privilege with just-in-time access elevation

module "pam_access_control" {
  source = "../../terraform-google-compliance-modules/modules/pam-access-control"

  org_id             = var.org_id
  project_id         = google_project.security.project_id
  logging_project_id = google_project.logging.project_id
  audit_dataset_id   = google_bigquery_dataset.audit_logs.dataset_id
  bigquery_location  = var.primary_region

  # Break glass configuration
  failsafe_account           = var.failsafe_account
  emergency_responders_group = "gcp-emergency-responders@${var.domain}"
  
  # Notification emails
  security_team_email   = "security@${var.domain}"
  compliance_team_email = "compliance@${var.domain}"
  ciso_email           = "ciso@${var.domain}"

  # Alert notification channels
  alert_notification_channels = [
    google_monitoring_notification_channel.security_email.id,
    google_monitoring_notification_channel.security_slack.id,
    google_monitoring_notification_channel.oncall_pagerduty.id
  ]

  # Standard PAM entitlements for organization
  standard_entitlements = {
    # Platform engineers - production access
    platform_engineer_prod = {
      eligible_principals = ["group:gcp-platform-engineers@${var.domain}"]
      role_bundle        = "platform_engineer"
      resource           = "//cloudresourcemanager.googleapis.com/folders/${google_folder.production.name}"
      resource_type      = "cloudresourcemanager.googleapis.com/Folder"
      access_window      = "normal"  # 2 hours
      approvers          = ["group:gcp-platform-leads@${var.domain}"]
      approvals_needed   = 1
      enable_fallback    = true
    }

    # Security team - org-wide read access
    security_analyst_org = {
      eligible_principals = ["group:gcp-security-analysts@${var.domain}"]
      role_bundle        = "security_analyst"
      resource           = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type      = "cloudresourcemanager.googleapis.com/Organization"
      access_window      = "extended"  # 4 hours
      approvers          = ["group:gcp-security-leads@${var.domain}"]
      approvals_needed   = 2
    }

    # Incident responders - emergency production access
    incident_responder_prod = {
      eligible_principals = ["group:gcp-incident-responders@${var.domain}"]
      custom_roles = [
        "roles/compute.admin",
        "roles/container.admin",
        "roles/logging.admin",
        "roles/monitoring.admin"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/folders/${google_folder.production.name}"
      resource_type    = "cloudresourcemanager.googleapis.com/Folder"
      access_window    = "emergency"  # 1 hour
      approvers        = ["group:gcp-incident-commanders@${var.domain}"]
      approvals_needed = 1
      enable_fallback  = true
      notification_emails = ["oncall@${var.domain}"]
    }

    # Compliance auditors - read-only org access
    compliance_auditor_org = {
      eligible_principals = ["group:gcp-compliance-auditors@${var.domain}"]
      custom_roles = [
        "roles/iam.securityReviewer",
        "roles/orgpolicy.policyViewer",
        "roles/logging.viewer",
        "roles/cloudasset.viewer"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "extended"  # 4 hours
      approvers        = ["group:gcp-compliance-leads@${var.domain}"]
      approvals_needed = 1
    }
  }
}

# Output PAM configuration for documentation
output "pam_configuration" {
  value = {
    break_glass = {
      eligible_users = [
        var.failsafe_account,
        "gcp-emergency-responders@${var.domain}"
      ]
      duration = "1 hour"
      approval = "Self-approval (emergency)"
      permissions = "Organization Owner"
    }
    standard_entitlements = keys(module.pam_access_control.standard_entitlements)
    monitoring = {
      alerts = "Break glass usage triggers immediate alerts"
      audit_logs = "All PAM activities logged to BigQuery"
      dashboards = "Real-time monitoring via Security Operations dashboard"
    }
  }
  description = "PAM and break glass configuration summary"
}