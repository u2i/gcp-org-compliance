# Organization-level DNS configuration for u2i.dev

# Create DNS project if it doesn't exist
resource "google_project" "dns_project" {
  project_id = "${var.project_prefix}-dns"
  name       = "DNS Management"
  org_id     = var.org_id
  
  billing_account = var.billing_account
  
  labels = {
    environment    = "production"
    compliance     = "iso27001-soc2-gdpr"
    data-residency = "eu"
    managed-by     = "terraform"
    cost-center    = "platform"
  }
}

# Enable Cloud DNS API
resource "google_project_service" "dns_api" {
  project = google_project.dns_project.project_id
  service = "dns.googleapis.com"
  
  disable_on_destroy = false
}

# Create the managed DNS zone for u2i.dev
resource "google_dns_managed_zone" "u2i_dev" {
  project     = google_project.dns_project.project_id
  name        = "u2i-dev"
  dns_name    = "u2i.dev."
  description = "Organization root domain for U2I"
  
  labels = {
    environment       = "production"
    compliance        = "iso27001-soc2-gdpr"
    data-residency    = "eu"
    managed-by        = "terraform"
    cost-center       = "platform"
  }
  
  dnssec_config {
    state = "on"
    non_existence = "nsec3"
  }
  
  depends_on = [google_project_service.dns_api]
}

# Export DNS name servers for domain registrar configuration
output "dns_nameservers" {
  description = "Name servers for u2i.dev - configure these at your domain registrar"
  value       = google_dns_managed_zone.u2i_dev.name_servers
}

# Create a record for the root domain
resource "google_dns_record_set" "u2i_dev_root" {
  project      = google_project.dns_project.project_id
  managed_zone = google_dns_managed_zone.u2i_dev.name
  name         = google_dns_managed_zone.u2i_dev.dns_name
  type         = "A"
  ttl          = 300
  
  # Placeholder - will be updated when we have actual IPs
  rrdatas = ["35.241.5.173"] # Google Cloud global anycast IP placeholder
}

# Create wildcard subdomain for future services
resource "google_dns_record_set" "u2i_dev_wildcard" {
  project      = google_project.dns_project.project_id
  managed_zone = google_dns_managed_zone.u2i_dev.name
  name         = "*.${google_dns_managed_zone.u2i_dev.dns_name}"
  type         = "CNAME"
  ttl          = 300
  
  rrdatas = [google_dns_managed_zone.u2i_dev.dns_name]
}

# Note: Specific application DNS records should be managed in their respective projects
# This allows each team to manage their own DNS without needing org-level permissions

# Create SPF record for email
resource "google_dns_record_set" "u2i_dev_spf" {
  project      = google_project.dns_project.project_id
  managed_zone = google_dns_managed_zone.u2i_dev.name
  name         = google_dns_managed_zone.u2i_dev.dns_name
  type         = "TXT"
  ttl          = 300
  
  rrdatas = ["\"v=spf1 include:_spf.google.com ~all\""]
}

# Create MX records for Google Workspace (if needed)
resource "google_dns_record_set" "u2i_dev_mx" {
  project      = google_project.dns_project.project_id
  managed_zone = google_dns_managed_zone.u2i_dev.name
  name         = google_dns_managed_zone.u2i_dev.dns_name
  type         = "MX"
  ttl          = 300
  
  rrdatas = [
    "1 aspmx.l.google.com.",
    "5 alt1.aspmx.l.google.com.",
    "5 alt2.aspmx.l.google.com.",
    "10 alt3.aspmx.l.google.com.",
    "10 alt4.aspmx.l.google.com."
  ]
}

# Monitoring and alerting for DNS
resource "google_monitoring_alert_policy" "dns_query_failures" {
  project      = google_project.dns_project.project_id
  display_name = "DNS Query Failures - u2i.dev"
  combiner     = "OR"
  
  conditions {
    display_name = "DNS query failure rate"
    
    condition_threshold {
      filter          = "resource.type=\"dns_query\" AND resource.label.\"target_name\"=\"u2i.dev\" AND metric.type=\"dns.googleapis.com/query/response_count\" AND metric.label.\"response_code\"!=\"NOERROR\""
      duration        = "300s"
      comparison      = "COMPARISON_GT"
      threshold_value = 10
      
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }
  
  notification_channels = []  # Add notification channels as needed
  
  enabled = true
  
  alert_strategy {
    auto_close = "1800s"
  }
}

# IAM policy for DNS zone management
# Commented out - group doesn't exist yet
# resource "google_dns_managed_zone_iam_member" "dns_admins" {
#   project      = google_project.dns_project.project_id
#   managed_zone = google_dns_managed_zone.u2i_dev.name
#   role         = "roles/dns.admin"
#   member       = "group:gcp-dns-admins@u2i.dev"
# }

# Export zone information for use by application teams
output "dns_zone_info" {
  description = "DNS zone information for application teams"
  value = {
    zone_name    = google_dns_managed_zone.u2i_dev.name
    dns_name     = google_dns_managed_zone.u2i_dev.dns_name
    project_id   = google_project.dns_project.project_id
  }
}

# Grant DNS editor permissions to specific service accounts
# This allows application teams to manage their own DNS records
resource "google_project_iam_member" "dns_editors" {
  for_each = toset([
    "terraform@u2i-tenant-webapp.iam.gserviceaccount.com",
    # Add more service accounts as needed
  ])
  
  project = google_project.dns_project.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${each.key}"
  
  condition {
    title       = "Subdomain restriction"
    description = "Only manage records under their app subdomain"
    expression  = "resource.name.startsWith('${split("@", each.key)[0]}.u2i.dev')"
  }
}