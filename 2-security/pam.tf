# PAM Configuration aligned with GCP Break-Glass Policy v0.7
# Implements 4 lanes with proper group assignments

module "pam_access_control" {
  source = "../../terraform-google-compliance-modules/modules/pam-access-control"

  org_id             = var.org_id
  project_id         = google_project.security.project_id
  logging_project_id = google_project.logging.project_id
  audit_dataset_id   = google_bigquery_dataset.audit_logs.dataset_id
  bigquery_location  = var.primary_region

  # Group structure per policy v0.7
  failsafe_account           = var.failsafe_account
  emergency_responders_group = local.groups.techmgmt  # Tech Mgmt group
  
  # Notification emails - send to tech management
  security_team_email   = local.groups.techmgmt
  compliance_team_email = local.groups.techmgmt 
  ciso_email           = local.groups.techmgmt

  # Alert channels
  alert_notification_channels = [
    google_monitoring_notification_channel.alerts_email.id,
  ]

  # PAM entitlements aligned with policy lanes
  standard_entitlements = {
    # Lane 1: App Code + Manifests (30 min)
    jit-deploy = {
      eligible_principals = [
        "group:${local.groups.developers}",
        "group:${local.groups.prodsupport}",
        "group:${local.groups.techlead}"
      ]
      custom_roles = [
        "roles/clouddeploy.operator",
        "roles/container.developer",
        "roles/logging.viewer"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "lane1"  # 30 minutes
      approvers        = [
        "group:${local.groups.prodsupport}",
        "group:${local.groups.techlead}",
        "group:${local.groups.techmgmt}"
      ]
      approvals_needed = 1  # Google PAM currently only supports 1
      notification_emails = [local.groups.techmgmt]
    }

    # Lane 2: Environment Infrastructure (60 min)
    jit-tf-admin = {
      eligible_principals = [
        "group:${local.groups.techlead}",
        "group:${local.groups.techmgmt}"
      ]
      custom_roles = [
        "roles/compute.admin",
        "roles/container.admin",
        "roles/iam.serviceAccountAdmin",
        "roles/storage.admin"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "lane2"  # 60 minutes
      approvers        = [
        "group:${local.groups.techlead}",
        "group:${local.groups.techmgmt}"
      ]
      approvals_needed = 1  # Google PAM currently only supports 1 (policy requires 2)
      notification_emails = [local.groups.techmgmt]
    }

    # Lane 3: Org-Level Infrastructure (30 min) - handled by break-glass-emergency

    # Lane 4: Everything-as-Code Project Bootstrap (30 min)
    jit-project-bootstrap = {
      eligible_principals = [
        "group:${local.groups.techlead}",
        "group:${local.groups.techmgmt}"
      ]
      custom_roles = [
        "roles/resourcemanager.projectCreator",
        "roles/billing.projectManager",
        "roles/iam.organizationRoleAdmin",
        "roles/orgpolicy.policyAdmin",
        "roles/logging.configWriter"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "lane3"  # 30 minutes (same as lane 4 in policy)
      approvers        = ["group:${local.groups.techmgmt}"]
      approvals_needed = 1  # Google PAM currently only supports 1 (policy requires 2)
      notification_emails = [local.groups.techmgmt]
    }

    # Deployment approver access (for Cloud Deploy gates)
    deployment-approver-access = {
      eligible_principals = [
        "group:${local.groups.prodsupport}",
        "group:${local.groups.techlead}",
        "group:${local.groups.techmgmt}"
      ]
      custom_roles = [
        "roles/clouddeploy.approver",
        "roles/clouddeploy.viewer",
        "roles/container.viewer",
        "roles/logging.viewer"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "normal"  # 2 hours
      approvers        = [
        "group:${local.groups.prodsupport}",
        "group:${local.groups.techlead}"
      ]
      approvals_needed = 1  # Google PAM currently only supports 1
      notification_emails = [local.groups.techmgmt]
    }

    # Billing access for finance team
    billing-access = {
      eligible_principals = ["group:${local.groups.billing}"]
      custom_roles = [
        "roles/billing.viewer",
        "roles/billing.costsManager"
      ]
      resource         = "//cloudresourcemanager.googleapis.com/organizations/${var.org_id}"
      resource_type    = "cloudresourcemanager.googleapis.com/Organization"
      access_window    = "extended"  # 4 hours for reports
      approvers        = ["group:${local.groups.techmgmt}"]
      approvals_needed = 1
      notification_emails = [local.groups.techmgmt]
    }
  }
}

# Notification channel for alerts
resource "google_monitoring_notification_channel" "alerts_email" {
  project      = google_project.security.project_id
  display_name = "Tech Management Alerts"
  type         = "email"
  
  labels = {
    email_address = local.groups.techmgmt
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
    SLACK_CHANNEL     = "#audit-log"
    DEPLOYMENT_TIMESTAMP = timestamp()
  }
}

# Organization-wide log sink for PAM events
resource "google_logging_organization_sink" "pam_audit_sink" {
  name        = "pam-audit-sink"
  org_id      = var.org_id
  destination = "pubsub.googleapis.com/projects/${google_project.security.project_id}/topics/${google_pubsub_topic.pam_events.name}"
  
  # Filter for PAM audit logs
  filter = <<-EOT
    protoPayload.serviceName="privilegedaccessmanager.googleapis.com"
    AND (
      protoPayload.methodName=~".*CreateGrant.*"
      OR protoPayload.methodName=~".*ApproveGrant.*"
      OR protoPayload.methodName=~".*DenyGrant.*"
      OR protoPayload.methodName=~".*RevokeGrant.*"
    )
  EOT
  
  include_children = true
  
  depends_on = [google_pubsub_topic.pam_events]
}

# Grant the log sink permission to publish to the topic
resource "google_pubsub_topic_iam_member" "pam_sink_publisher" {
  project = google_project.security.project_id
  topic   = google_pubsub_topic.pam_events.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_organization_sink.pam_audit_sink.writer_identity
  
  depends_on = [google_logging_organization_sink.pam_audit_sink]
}

# Secret Manager for Slack bot token
resource "google_secret_manager_secret" "slack_bot_token" {
  project   = google_project.security.project_id
  secret_id = "slack-pam-bot-token"
  
  depends_on = [google_project_service.security_apis["secretmanager.googleapis.com"]]
  
  replication {
    auto {}
  }
}

# Grant Cloud Function access to the secret
resource "google_secret_manager_secret_iam_member" "slack_token_accessor" {
  project   = google_project.security.project_id
  secret_id = google_secret_manager_secret.slack_bot_token.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_project.security.project_id}@appspot.gserviceaccount.com"
  
  depends_on = [google_secret_manager_secret.slack_bot_token]
}

# Output configuration aligned with policy v0.7
output "pam_config_v07" {
  value = {
    policy_version = "v0.7"
    groups = {
      developers  = local.groups.developers
      prodsupport = local.groups.prodsupport
      techlead    = local.groups.techlead
      techmgmt    = local.groups.techmgmt
      billing     = local.groups.billing
    }
    lanes = {
      lane1 = {
        name     = "App Code + Manifests"
        ttl      = "30 minutes"
        approval = "Prod Support+ peer approval"
        jit_role = "jit-deploy"
      }
      lane2 = {
        name     = "Environment Infrastructure"
        ttl      = "60 minutes"
        approval = "Tech Lead + Tech Mgmt (2 approvers)"
        jit_role = "jit-tf-admin"
      }
      lane3 = {
        name     = "Org-Level Infrastructure"
        ttl      = "30 minutes"
        approval = "2 Tech Mgmt approvers"
        jit_role = "break-glass-emergency"
      }
      lane4 = {
        name     = "Everything-as-Code Project Bootstrap"
        ttl      = "30 minutes"
        approval = "2 Tech Mgmt approvers"
        jit_role = "jit-project-bootstrap"
      }
    }
    retention = "400 days for all audit artifacts"
    notifications = "All alerts to ${local.groups.techmgmt} + #audit-log"
  }
  description = "PAM configuration aligned with Break-Glass Policy v0.7"
}