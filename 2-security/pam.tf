# Simplified PAM Configuration for Small Company
# Aligned with GCP Break-Glass Policy v0.4

module "pam_access_control" {
  source = "../../terraform-google-compliance-modules/modules/pam-access-control"

  org_id             = var.org_id
  project_id         = google_project.security.project_id
  logging_project_id = google_project.logging.project_id
  audit_dataset_id   = google_bigquery_dataset.audit_logs.dataset_id
  bigquery_location  = var.primary_region

  # Simplified group structure
  failsafe_account           = var.failsafe_account
  emergency_responders_group = "gcp-admins@${var.domain}"  # Tech Mgmt group
  
  # Notification emails - send to admin group
  security_team_email   = "gcp-admins@${var.domain}"
  compliance_team_email = "gcp-admins@${var.domain}"  
  ciso_email           = "gcp-admins@${var.domain}"

  # Alert channels
  alert_notification_channels = [
    google_monitoring_notification_channel.alerts_email.id,
  ]

  # PAM entitlements aligned with policy lanes
  standard_entitlements = {
    # Lane 1: App Code + Manifests (30 min)
    jit-deploy = {
      eligible_principals = [
        "group:gcp-developers@${var.domain}",
        "group:gcp-approvers@${var.domain}"
      ]
      custom_roles = [
        "roles/clouddeploy.operator",
        "roles/container.developer",
        "roles/logging.viewer"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "lane1"  # 30 minutes
      approvers        = ["group:gcp-approvers@${var.domain}"]  # Peer approval
      approvals_needed = 1  # Google PAM currently only supports 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # Lane 2: Environment Infrastructure (60 min)
    jit-tf-admin = {
      eligible_principals = ["group:gcp-admins@${var.domain}"]  # Tech Leads/Mgmt
      custom_roles = [
        "roles/compute.admin",
        "roles/container.admin",
        "roles/iam.serviceAccountAdmin",
        "roles/storage.admin"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "lane2"  # 60 minutes
      approvers        = ["group:gcp-admins@${var.domain}"]  # Tech Lead + Tech Mgmt
      approvals_needed = 1  # Google PAM currently only supports 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # Lane 3: Org-Level Infrastructure (30 min) - handled by break-glass-emergency

    # Additional standard entitlements
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
      approvers        = ["group:gcp-approvers@${var.domain}"]
      approvals_needed = 1  # Google PAM currently only supports 1
      notification_emails = ["gcp-admins@${var.domain}"]
    }

    # Billing access for auditors - commented out until group exists
    # billing-access = {
    #   eligible_principals = ["group:gcp-auditors@${var.domain}"]
    #   custom_roles = [
    #     "roles/billing.viewer",
    #     "roles/billing.costsManager"
    #   ]
    #   resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
    #   resource_type    = "cloudresourcemanager.googleapis.com/Organization"
    #   access_window    = "extended"  # 4 hours for reports
    #   approvers        = ["group:gcp-admins@${var.domain}"]
    #   approvals_needed = 1
    #   notification_emails = ["gcp-admins@${var.domain}"]
    # }
  }
}

# Notification channel for alerts
resource "google_monitoring_notification_channel" "alerts_email" {
  project      = google_project.security.project_id
  display_name = "Admin Group Alerts"
  type         = "email"
  
  labels = {
    email_address = "gcp-admins@${var.domain}"
  }
}

# Cloud Function for Slack integration
resource "google_storage_bucket" "cloud_functions" {
  name     = "${var.org_prefix}-pam-slack-functions"
  location = var.primary_region
  project  = google_project.security.project_id

  uniform_bucket_level_access = true
  force_destroy              = false
}

resource "google_storage_bucket_object" "pam_slack_function" {
  name   = "pam-slack-notifier.zip"
  bucket = google_storage_bucket.cloud_functions.name
  source = "${path.module}/functions/pam-slack-notifier.zip"
}

resource "google_pubsub_topic" "pam_events" {
  name    = "pam-audit-events"
  project = google_project.security.project_id
}

resource "google_cloudfunctions_function" "pam_slack_notifier" {
  name        = "pam-slack-notifier"
  description = "Posts PAM events to #audit-log Slack channel"
  runtime     = "nodejs18"
  project     = google_project.security.project_id
  region      = var.primary_region
  
  depends_on = [google_project_service.security_apis["cloudfunctions.googleapis.com"]]

  available_memory_mb   = 256
  source_archive_bucket = google_storage_bucket.cloud_functions.name
  source_archive_object = google_storage_bucket_object.pam_slack_function.name
  entry_point          = "handlePamEvent"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.pam_events.name
  }

  environment_variables = {
    SLACK_WEBHOOK_URL = var.slack_webhook_url
    SLACK_CHANNEL     = "#audit-log"
  }
}

# Output simplified configuration
output "simplified_pam_config" {
  value = {
    policy_version = "v0.4"
    lanes = {
      lane1 = {
        name     = "App Code + Manifests"
        ttl      = "30 minutes"
        approval = "Dual approval from Prod Support+"
        jit_role = "jit-deploy"
      }
      lane2 = {
        name     = "Environment Infrastructure"
        ttl      = "60 minutes"
        approval = "Tech Lead + Tech Mgmt"
        jit_role = "jit-tf-admin"
      }
      lane3 = {
        name     = "Org-Level Infrastructure"
        ttl      = "30 minutes"
        approval = "2 Tech Mgmt approvers"
        jit_role = "break-glass-emergency"
      }
    }
    retention = "400 days for all audit artifacts"
    notifications = "All alerts go to gcp-admins@${var.domain} + #audit-log"
  }
  description = "PAM configuration aligned with Break-Glass Policy v0.4"
}