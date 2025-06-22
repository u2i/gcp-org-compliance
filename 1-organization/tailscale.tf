# Tailscale Organization-wide Infrastructure
# Provides secure access to all GCP resources without traditional VPN

# Create dedicated project for Tailscale infrastructure
resource "google_project" "tailscale" {
  name            = "Tailscale Infrastructure"
  project_id      = "${var.project_prefix}-tailscale-infra"
  folder_id       = module.org_structure.folder_ids["shared-services"]
  billing_account = var.billing_account
  
  labels = {
    service     = "tailscale"
    environment = "production"
    compliance  = "infrastructure"
  }
}

# Enable required APIs
resource "google_project_service" "tailscale_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com"
  ])
  
  project = google_project.tailscale.project_id
  service = each.value
}

# Service account for Tailscale routers
resource "google_service_account" "tailscale_router" {
  account_id   = "tailscale-router"
  display_name = "Tailscale Subnet Router"
  description  = "Service account for Tailscale subnet routers to access organization resources"
  project      = google_project.tailscale.project_id
}

# Grant organization-wide read permissions for network discovery
resource "google_organization_iam_member" "tailscale_permissions" {
  for_each = toset([
    "roles/viewer",
    "roles/compute.networkViewer",
    "roles/container.viewer"
  ])
  
  org_id = var.org_id
  role   = each.key
  member = "serviceAccount:${google_service_account.tailscale_router.email}"
}

# Create secret for Tailscale auth key
resource "google_secret_manager_secret" "tailscale_auth_key" {
  secret_id = "tailscale-auth-key"
  project   = google_project.tailscale.project_id
  
  labels = {
    service     = "tailscale"
    type        = "auth-key"
    managed_by  = "terraform"
  }
  
  replication {
    automatic = true
  }
  
  depends_on = [google_project_service.tailscale_apis["secretmanager.googleapis.com"]]
}

# Grant secret access to router service account
resource "google_secret_manager_secret_iam_member" "tailscale_secret_access" {
  project   = google_project.tailscale.project_id
  secret_id = google_secret_manager_secret.tailscale_auth_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tailscale_router.email}"
}

# NOTE: The auth key must be manually added to Secret Manager first
# Run: echo -n "tskey-auth-xxxxx" | gcloud secrets versions add tailscale-auth-key --project=PROJECT_ID --data-file=-

# OAuth automation resources are included via tailscale-oauth.tf in the same directory
# They will be automatically applied when enable_auto_key_rotation = true

# Deploy Tailscale infrastructure
module "tailscale_org_setup" {
  source = "../../../u2i-terraform-modules/tailscale-org-setup"
  
  organization_id = var.org_id
  billing_account = var.billing_account
  
  # For initial deployment, use variable. After secret is created, switch to data source
  tailscale_auth_key = var.tailscale_auth_key
  
  # Deploy in key regions where we have infrastructure
  regions = [
    "us-central1",
    "europe-west1", 
    "europe-west4"
  ]
  
  # Override the default tailscale module regions variable
  # regions = var.tailscale_regions
  
  # Advertise all private ranges including GKE
  advertise_routes = [
    "10.0.0.0/8",      # Standard private range
    "172.16.0.0/12",   # Standard private range  
    "192.168.0.0/16",  # Standard private range
    "100.64.0.0/10",   # GKE pod ranges
    "10.96.0.0/11",    # GKE service ranges
    "10.128.0.0/9"     # GCP VPC ranges
  ]
  
  # Alert compliance team on issues
  notification_channels = []  # Add after monitoring setup
  
  tags = {
    compliance = "network-access"
    owner      = "security-team"
  }
  
  depends_on = [
    google_project_service.tailscale_apis
  ]
}

# Allow Tailscale access through organization firewall policies
# NOTE: Uncomment when organization security policy is available
# resource "google_compute_organization_security_policy_rule" "allow_tailscale" {
#   policy_id   = module.security_baseline.organization_security_policy_id
#   action      = "allow"
#   direction   = "INGRESS"
#   priority    = 1000
#   
#   match {
#     config {
#       src_ip_ranges = ["100.64.0.0/10"]  # Tailscale CGNAT range
#       layer4_config {
#         ip_protocol = "all"
#       }
#     }
#   }
#   
#   description = "Allow Tailscale mesh network traffic"
#   
#   depends_on = [module.security_baseline]
# }

# Create firewall rules in shared VPC for Tailscale
resource "google_compute_firewall" "allow_tailscale_udp" {
  name    = "allow-tailscale-udp"
  project = google_project.tailscale.project_id
  network = "default"  # Update to your shared VPC
  
  allow {
    protocol = "udp"
    ports    = ["41641"]
  }
  
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tailscale-router"]
  
  description = "Allow Tailscale WireGuard traffic"
}

# Output connection instructions
output "tailscale_setup_instructions" {
  value = <<-EOT
    ===== Tailscale Setup Instructions =====
    
    1. STORE AUTH KEY in Secret Manager:
       - Generate key at: https://login.tailscale.com/admin/settings/keys
       - Store it: 
         echo -n "tskey-auth-xxxxx" | gcloud secrets versions add ${google_secret_manager_secret.tailscale_auth_key.secret_id} \
           --project=${google_project.tailscale.project_id} --data-file=-
    
    2. APPLY Tailscale infrastructure:
       terraform apply -target=module.tailscale_org_setup
    
    3. APPROVE ROUTES in Tailscale console:
       - Go to: https://login.tailscale.com/admin/machines
       - Approve advertised routes for each region
    
    4. ACCESS GCP resources:
       - Install Tailscale: https://tailscale.com/download
       - Connect and access any private IP in GCP!
    
    Project: ${google_project.tailscale.project_id}
    Regions: us-central1, europe-west1, europe-west4
  EOT
  
  sensitive = false
}

# Export for use in other modules
output "tailscale_project_id" {
  value       = google_project.tailscale.project_id
  description = "Project ID where Tailscale infrastructure is deployed"
}

output "tailscale_router_instances" {
  value       = module.tailscale_org_setup.router_instances
  description = "Tailscale router instance details by region"
}