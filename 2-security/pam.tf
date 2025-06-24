# Simplified PAM Configuration for Small Company
# This replaces the complex pam.tf with a streamlined version

module "pam_access_control" {
  source = "../../terraform-google-compliance-modules/modules/pam-access-control"

  org_id             = var.org_id
  project_id         = google_project.security.project_id
  logging_project_id = google_project.logging.project_id
  audit_dataset_id   = google_bigquery_dataset.audit_logs.dataset_id
  bigquery_location  = var.primary_region

  # Simplified group structure
  failsafe_account           = var.failsafe_account
  emergency_responders_group = "gcp-admins@${var.domain}"  # Combined admin group
  
  # Notification emails - send to admin group
  security_team_email   = "gcp-admins@${var.domain}"
  compliance_team_email = "gcp-admins@${var.domain}"  
  ciso_email           = "gcp-admins@${var.domain}"

  # Alert channels
  alert_notification_channels = [
    google_monitoring_notification_channel.alerts_email.id,
    # Add Slack when ready: google_monitoring_notification_channel.alerts_slack.id
  ]

  # Simplified PAM entitlements for small company
  standard_entitlements = {
    # 1. Admin elevation - for infrastructure changes
    admin-elevation = {
      eligible_principals = ["group:gcp-admins@${var.domain}"]
      custom_roles = [
        "roles/admin"  # Full admin access (owner not supported in PAM)
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "normal"  # 2 hours
      approvers        = ["group:gcp-admins@${var.domain}"]  # Peer approval within admin group
      approvals_needed = 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # 2. Deployment approval elevation - for approvers who need temporary access
    deployment-approver-access = {
      eligible_principals = ["group:gcp-approvers@${var.domain}"]
      custom_roles = [
        "roles/clouddeploy.approver",
        "roles/clouddeploy.viewer",
        "roles/container.viewer",
        "roles/logging.viewer"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "normal"  # 2 hours
      approvers        = ["group:gcp-approvers@${var.domain}"]  # Self-approval within approvers
      approvals_needed = 1  # Google requires at least 1, but approvers can self-approve
    }

    # 3. Developer production access - for deployments and debugging
    developer-prod-access = {
      eligible_principals = [
        "group:gcp-developers@${var.domain}",
        "group:gcp-admins@${var.domain}"  # Admins can also use this
      ]
      custom_roles = [
        "roles/compute.admin",
        "roles/container.admin",
        "roles/clouddeploy.operator",
        "roles/logging.viewer",
        "roles/monitoring.editor"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "normal"  # 2 hours
      approvers        = ["group:gcp-admins@${var.domain}"]
      approvals_needed = 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # 4. Billing access - for finance team if needed
    billing-access = {
      eligible_principals = ["group:gcp-auditors@${var.domain}"]
      custom_roles = [
        "roles/billing.viewer",
        "roles/billing.costsManager"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "extended"  # 4 hours for reports
      approvers        = ["group:gcp-admins@${var.domain}"]
      approvals_needed = 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # 5. Service account elevation - for CI/CD automation
    cicd-automation = {
      eligible_principals = [
        "serviceAccount:github-actions@${google_project.security.project_id}.iam.gserviceaccount.com"
      ]
      custom_roles = [
        "roles/resourcemanager.projectIamAdmin",
        "roles/iam.serviceAccountAdmin",
        "roles/clouddeploy.admin"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "emergency"  # 1 hour - using emergency window for automation
      approvers        = ["serviceAccount:github-actions@${google_project.security.project_id}.iam.gserviceaccount.com"]
      approvals_needed = 1  # Google requires at least 1, service account can self-approve
      notification_emails = ["gcp-admins@${var.domain}"]
    }
  }
}

# Simplified notification channel - just email to start
resource "google_monitoring_notification_channel" "alerts_email" {
  project      = google_project.security.project_id
  display_name = "Admin Group Alerts"
  type         = "email"
  
  labels = {
    email_address = "gcp-admins@${var.domain}"
  }
}

# Output simplified configuration
output "simplified_pam_config" {
  value = {
    groups = {
      admins     = "gcp-admins@${var.domain}"
      approvers  = "gcp-approvers@${var.domain}"
      developers = "gcp-developers@${var.domain}"
      auditors   = "gcp-auditors@${var.domain}"
    }
    break_glass = {
      who      = "gcp-admins@${var.domain} + failsafe account"
      duration = "1 hour"
      approval = "Self-approval for emergencies"
    }
    standard_access = {
      admin-elevation           = "2 hours with peer approval"
      deployment-approver-access = "2 hours with self-approval"
      developer-prod-access     = "2 hours with admin approval"
      billing-access            = "4 hours with admin approval"
      cicd-automation          = "30 minutes auto-approved"
    }
    notifications = "All alerts go to gcp-admins@${var.domain}"
  }
  description = "Simplified PAM configuration for small company"
}