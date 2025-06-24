# Failsafe Account Monitoring
# Implements policy v0.7 section 3.1 and 6 requirements

# Alert on failsafe account usage
resource "google_monitoring_alert_policy" "failsafe_account_alert" {
  project      = google_project.security.project_id
  display_name = "Failsafe Account Login Alert"
  combiner     = "OR"
  
  conditions {
    display_name = "Failsafe account u2i-failsafe@google.com logged in"
    
    condition_matched_log {
      filter = <<-EOT
        protoPayload.authenticationInfo.principalEmail="u2i-failsafe@google.com"
        AND protoPayload.serviceName="cloudresourcemanager.googleapis.com"
        AND protoPayload.methodName=~"^google.iam.admin.v1.ListServiceAccounts|google.iam.v1.IAMPolicy.SetIamPolicy|google.cloud.resourcemanager.v3.Projects.Create"
      EOT
    }
  }
  
  notification_channels = [
    google_monitoring_notification_channel.alerts_email.id,
    google_monitoring_notification_channel.security_email.id,
  ]
  
  alert_strategy {
    auto_close = "86400s"  # 24 hours
    notification_rate_limit {
      period = "300s"  # Alert immediately, then every 5 minutes
    }
  }
  
  documentation {
    content = <<-EOT
      CRITICAL: Failsafe account u2i-failsafe@google.com has been used.
      
      This indicates a severe outage scenario where both PAM and Workspace SSO are unavailable.
      
      Immediate actions:
      1. Verify this is a legitimate emergency per policy section 3.1
      2. Confirm Tech Mgmt quorum (CEO + Tech Lead) authorized this
      3. Check #audit-log for emergency declaration
      4. Monitor all actions taken by the account
      5. Ensure credentials are rotated after use
      6. Create retro-PR within 24 hours
      
      Policy reference: GCP Break-Glass Policy v0.7 section 3.1
    EOT
  }
}

# Log sink specifically for failsafe account activities
resource "google_logging_organization_sink" "failsafe_audit" {
  name             = "failsafe-account-audit"
  org_id           = var.org_id
  include_children = true
  
  filter = <<-EOT
    protoPayload.authenticationInfo.principalEmail="u2i-failsafe@google.com"
    OR protoPayload.authenticationInfo.principalSubject="u2i-failsafe@google.com"
  EOT
  
  destination = "bigquery.googleapis.com/projects/${google_project.logging.project_id}/datasets/${google_bigquery_dataset.audit_logs.dataset_id}"
  
  bigquery_options {
    use_partitioned_tables = true
  }
}

# Dashboard for failsafe account monitoring
resource "google_monitoring_dashboard" "failsafe_monitoring" {
  project        = google_project.security.project_id
  dashboard_json = jsonencode({
    displayName = "Failsafe Account Monitoring"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width  = 6
          height = 4
          widget = {
            title = "Failsafe Account Login Events (Last 30 Days)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "metric.type=\"logging.googleapis.com/user/failsafe-account-usage\""
                  }
                }
              }]
            }
          }
        },
        {
          width  = 6
          height = 4
          xPos   = 6
          widget = {
            title = "Actions by Failsafe Account"
            logsPanel = {
              filter = "protoPayload.authenticationInfo.principalEmail=\"u2i-failsafe@google.com\""
            }
          }
        }
      ]
    }
  })
}

# Metric for failsafe account usage
resource "google_logging_metric" "failsafe_usage" {
  project = google_project.logging.project_id
  name    = "failsafe-account-usage"
  filter  = "protoPayload.authenticationInfo.principalEmail=\"u2i-failsafe@google.com\""
  
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"
    labels {
      key         = "method"
      value_type  = "STRING"
      description = "The API method called"
    }
    labels {
      key         = "service"
      value_type  = "STRING"
      description = "The service name"
    }
  }
  
  label_extractors = {
    "method"  = "EXTRACT(protoPayload.methodName)"
    "service" = "EXTRACT(protoPayload.serviceName)"
  }
}

output "failsafe_monitoring" {
  value = {
    alert_policy   = google_monitoring_alert_policy.failsafe_account_alert.name
    log_sink       = google_logging_organization_sink.failsafe_audit.name
    dashboard_url  = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.failsafe_monitoring.id}?project=${google_project.security.project_id}"
    account_email  = "u2i-failsafe@google.com"
  }
  description = "Failsafe account monitoring configuration"
}