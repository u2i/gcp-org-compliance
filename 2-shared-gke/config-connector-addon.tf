# Enable Config Connector addon on both clusters
# This allows managing GCP resources directly from Kubernetes

# Update the Production GKE Autopilot Cluster
# Note: This needs to be added to the existing google_container_cluster.prod_autopilot resource
# Add this block inside the resource:
#
#   addons_config {
#     config_connector_config {
#       enabled = true
#     }
#   }

# Update the Non-Production GKE Autopilot Cluster  
# Note: This needs to be added to the existing google_container_cluster.nonprod_autopilot resource
# Add this block inside the resource:
#
#   addons_config {
#     config_connector_config {
#       enabled = true
#     }
#   }

# Config Connector Service Account for each cluster
resource "google_service_account" "config_connector_sa" {
  for_each = {
    prod    = google_project.gke_projects["u2i-gke-prod"].project_id
    nonprod = google_project.gke_projects["u2i-gke-nonprod"].project_id
  }

  project      = each.value
  account_id   = "config-connector"
  display_name = "Config Connector Service Account"
  description  = "Service account for Config Connector to manage GCP resources"
}

# Grant necessary permissions to Config Connector service accounts
resource "google_project_iam_member" "config_connector_roles" {
  for_each = {
    for pair in setproduct(["prod", "nonprod"], [
      "roles/owner",  # For full resource management (reduce in production)
    ]) : "${pair[0]}-${pair[1]}" => {
      env  = pair[0]
      role = pair[1]
    }
  }

  project = each.value.env == "prod" ? google_project.gke_projects["u2i-gke-prod"].project_id : google_project.gke_projects["u2i-gke-nonprod"].project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.config_connector_sa[each.value.env].email}"
}

# Workload Identity binding for Config Connector
resource "google_service_account_iam_member" "config_connector_workload_identity" {
  for_each = {
    prod    = google_project.gke_projects["u2i-gke-prod"].project_id
    nonprod = google_project.gke_projects["u2i-gke-nonprod"].project_id
  }

  service_account_id = google_service_account.config_connector_sa[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${each.value}.svc.id.goog[cnrm-system/cnrm-controller-manager]"
}