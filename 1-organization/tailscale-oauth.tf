# Tailscale OAuth Application for Automated Key Management
# This eliminates the need for manual auth key rotation

# Option 1: OAuth Application (Recommended for automation)
# Creates OAuth credentials that can programmatically generate auth keys

resource "google_secret_manager_secret" "tailscale_oauth_client_id" {
  secret_id = "tailscale-oauth-client-id"
  project   = google_project.tailscale.project_id
  
  labels = {
    service = "tailscale"
    type    = "oauth-client-id"
  }
  
  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret" "tailscale_oauth_client_secret" {
  secret_id = "tailscale-oauth-client-secret"
  project   = google_project.tailscale.project_id
  
  labels = {
    service = "tailscale"
    type    = "oauth-client-secret"
  }
  
  replication {
    automatic = true
  }
}

# Grant access to the OAuth secrets
resource "google_secret_manager_secret_iam_member" "tailscale_oauth_access" {
  for_each = toset([
    google_secret_manager_secret.tailscale_oauth_client_id.secret_id,
    google_secret_manager_secret.tailscale_oauth_client_secret.secret_id
  ])
  
  project   = google_project.tailscale.project_id
  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.tailscale_router.email}"
}

# Cloud Function to automatically generate auth keys using OAuth
resource "google_cloudfunctions2_function" "tailscale_key_generator" {
  count = var.enable_auto_key_rotation ? 1 : 0
  
  name     = "tailscale-key-generator"
  location = "us-central1"
  project  = google_project.tailscale.project_id
  
  description = "Automatically generates Tailscale auth keys using OAuth"
  
  build_config {
    runtime     = "python311"
    entry_point = "generate_auth_key"
    source {
      inline_source {
        path = "main.py"
        content = file("${path.module}/functions/tailscale-key-generator/main.py")
      }
      
      inline_source {
        path = "requirements.txt"
        content = <<-EOT
          google-cloud-secret-manager==2.16.0
          requests==2.31.0
          functions-framework==3.4.0
        EOT
      }
    }
  }
  
  service_config {
    max_instance_count = 1
    min_instance_count = 0
    available_memory   = "256M"
    timeout_seconds    = 60
    
    environment_variables = {
      PROJECT_ID = google_project.tailscale.project_id
      TAILNET    = var.tailscale_tailnet  # e.g., "example.com" or "tailnet-id"
    }
    
    service_account_email = google_service_account.tailscale_key_generator[0].email
  }
}

# Service account for the key generator function
resource "google_service_account" "tailscale_key_generator" {
  count = var.enable_auto_key_rotation ? 1 : 0
  
  account_id   = "tailscale-key-generator"
  display_name = "Tailscale Key Generator"
  description  = "Generates auth keys for Tailscale routers"
  project      = google_project.tailscale.project_id
}

# Permissions for key generator
resource "google_project_iam_member" "key_generator_permissions" {
  count = var.enable_auto_key_rotation ? 1 : 0
  
  project = google_project.tailscale.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.tailscale_key_generator[0].email}"
}

# Cloud Scheduler to run key generation periodically
resource "google_cloud_scheduler_job" "tailscale_key_rotation" {
  count = var.enable_auto_key_rotation ? 1 : 0
  
  name        = "tailscale-key-rotation"
  description = "Rotates Tailscale auth keys monthly"
  project     = google_project.tailscale.project_id
  region      = "us-central1"
  
  schedule         = "0 2 1 * *"  # Run at 2 AM on the 1st of each month
  time_zone        = "UTC"
  attempt_deadline = "320s"
  
  http_target {
    uri         = google_cloudfunctions2_function.tailscale_key_generator[0].service_config[0].uri
    http_method = "POST"
    
    oidc_token {
      service_account_email = google_service_account.tailscale_key_generator[0].email
    }
  }
}

# Option 2: Device Authorization (No keys needed!)
# This is the simplest approach - each VM authorizes itself

resource "google_compute_instance_template" "tailscale_router_device_auth" {
  for_each = var.use_device_authorization ? toset(var.regions) : []
  
  name_prefix  = "tailscale-router-device-${each.value}-"
  project      = google_project.tailscale.project_id
  region       = each.value
  machine_type = var.instance_type

  disk {
    source_image = "ubuntu-os-cloud/ubuntu-2204-lts"
    auto_delete  = true
    boot         = true
    disk_size_gb = 10
  }

  network_interface {
    network    = google_compute_network.tailscale.id
    subnetwork = google_compute_subnetwork.tailscale[each.value].id
    
    access_config {
      # Ephemeral public IP
    }
  }

  can_ip_forward = true

  metadata = {
    enable-oslogin = "TRUE"
    startup-script = templatefile("${path.module}/startup-script-device-auth.sh", {
      advertise_routes = join(",", var.advertise_routes)
      hostname         = "gcp-${each.value}"
      tailnet          = var.tailscale_tailnet
      tags             = "tag:subnet-router,tag:gcp"
    })
  }

  tags = ["tailscale-router"]

  service_account {
    email  = google_service_account.tailscale_router.email
    scopes = ["cloud-platform"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Option 3: Tailscale Operator for GKE (For Kubernetes workloads)
# Deploy this in your GKE clusters for automatic pod/service access

resource "kubernetes_namespace" "tailscale_operator" {
  count = var.deploy_k8s_operator ? 1 : 0
  
  metadata {
    name = "tailscale-system"
  }
}

resource "helm_release" "tailscale_operator" {
  count = var.deploy_k8s_operator ? 1 : 0
  
  name       = "tailscale-operator"
  repository = "https://helm.tailscale.com"
  chart      = "tailscale-operator"
  namespace  = kubernetes_namespace.tailscale_operator[0].metadata[0].name
  
  set {
    name  = "oauth.clientId"
    value = var.tailscale_oauth_client_id
  }
  
  set_sensitive {
    name  = "oauth.clientSecret"
    value = var.tailscale_oauth_client_secret
  }
  
  set {
    name  = "defaultTags"
    value = "tag:k8s,tag:gcp"
  }
}

# Variables for OAuth setup
variable "enable_auto_key_rotation" {
  description = "Enable automatic auth key rotation using OAuth"
  type        = bool
  default     = false
}

variable "use_device_authorization" {
  description = "Use device authorization instead of auth keys (requires manual approval)"
  type        = bool
  default     = false
}

variable "deploy_k8s_operator" {
  description = "Deploy Tailscale operator in GKE clusters"
  type        = bool
  default     = false
}

variable "tailscale_tailnet" {
  description = "Your Tailscale tailnet name (e.g., 'example.com' or tailnet ID)"
  type        = string
  default     = ""
}

variable "tailscale_oauth_client_id" {
  description = "Tailscale OAuth client ID (from https://login.tailscale.com/admin/settings/oauth)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "Tailscale OAuth client secret"
  type        = string
  default     = ""
  sensitive   = true
}

# Output instructions for OAuth setup
output "oauth_setup_instructions" {
  value = var.enable_auto_key_rotation ? <<-EOT
    === OAuth Setup Instructions ===
    
    1. Create OAuth application at:
       https://login.tailscale.com/admin/settings/oauth
       
       - Name: "GCP Subnet Routers"
       - Scopes: devices:write
       - Copy Client ID and Secret
    
    2. Store credentials in Secret Manager:
       echo -n "CLIENT_ID" | gcloud secrets versions add tailscale-oauth-client-id \
         --project=${google_project.tailscale.project_id} --data-file=-
       
       echo -n "CLIENT_SECRET" | gcloud secrets versions add tailscale-oauth-client-secret \
         --project=${google_project.tailscale.project_id} --data-file=-
    
    3. Auth keys will now be automatically generated monthly!
       No more manual rotation needed.
  EOT : "OAuth key rotation not enabled"
}