output "security_project_id" {
  value       = google_project.security.project_id
  description = "Security operations project ID"
}

output "logging_project_id" {
  value       = google_project.logging.project_id
  description = "Centralized logging project ID"
}

output "audit_dataset_id" {
  value       = google_bigquery_dataset.audit_logs.dataset_id
  description = "BigQuery dataset for audit logs"
}

output "notification_channels" {
  value = {
    security_email    = google_monitoring_notification_channel.security_email.id
    security_slack    = google_monitoring_notification_channel.security_slack.id
    oncall_pagerduty = google_monitoring_notification_channel.oncall_pagerduty.id
  }
  description = "Notification channel IDs for alerts"
}

output "pam_status" {
  value = {
    deployed = true
    break_glass_enabled = true
    entitlements_count = length(keys(module.pam_access_control.standard_entitlements))
  }
  description = "PAM deployment status"
}