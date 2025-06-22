# Simplified Outputs for Belgium GKE Deployment

output "projects_created" {
  description = "Created GKE projects"
  value = {
    for k, v in google_project.gke_projects : k => {
      project_id = v.project_id
      number     = v.number
    }
  }
}

output "gke_clusters" {
  description = "GKE cluster connection information"
  value = {
    production = {
      project_id   = google_container_cluster.prod_autopilot.project
      cluster_name = google_container_cluster.prod_autopilot.name
      location     = google_container_cluster.prod_autopilot.location
      endpoint     = google_container_cluster.prod_autopilot.endpoint
      
      connect_command = "gcloud container clusters get-credentials ${google_container_cluster.prod_autopilot.name} --location=${google_container_cluster.prod_autopilot.location} --project=${google_container_cluster.prod_autopilot.project}"
    }
    
    non_production = {
      project_id   = google_container_cluster.nonprod_autopilot.project
      cluster_name = google_container_cluster.nonprod_autopilot.name
      location     = google_container_cluster.nonprod_autopilot.location
      endpoint     = google_container_cluster.nonprod_autopilot.endpoint
      
      connect_command = "gcloud container clusters get-credentials ${google_container_cluster.nonprod_autopilot.name} --location=${google_container_cluster.nonprod_autopilot.location} --project=${google_container_cluster.nonprod_autopilot.project}"
    }
  }
  sensitive = true
}

output "network_info" {
  description = "Network configuration"
  value = {
    vpc_name = google_compute_network.gke_shared_network.name
    vpc_project = google_compute_network.gke_shared_network.project
    prod_subnet = google_compute_subnetwork.prod_subnet.name
    nonprod_subnet = google_compute_subnetwork.nonprod_subnet.name
    region = var.primary_region
  }
}

output "deployment_summary" {
  description = "Belgium deployment summary"
  value = {
    region = var.primary_region
    compliance_frameworks = ["ISO 27001", "SOC 2 Type II", "GDPR"]
    data_residency = "EU"
    clusters_deployed = 2
    autopilot_enabled = true
    private_clusters = true
    
    next_steps = [
      "1. Verify cluster connectivity",
      "2. Set up tenant namespaces",
      "3. Configure monitoring and compliance",
      "4. Deploy tenant applications"
    ]
  }
}