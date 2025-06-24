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
    security_slack    = try(google_monitoring_notification_channel.security_slack[0].id, "")
    oncall_pagerduty = try(google_monitoring_notification_channel.oncall_pagerduty[0].id, "")
  }
  description = "Notification channel IDs for alerts"
}

output "pam_status" {
  value = {
    deployed = true
    break_glass_enabled = true
    break_glass_entitlement = module.pam_access_control.break_glass_entitlement
  }
  description = "PAM deployment status"
}