# Simplified Belgium GKE Deployment - Core Infrastructure Only
# This version deploys the essential components first

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0"
    }
  }
  
  backend "gcs" {
    bucket = "u2i-tfstate"
    prefix = "shared-gke"
  }
}

provider "google" {
  user_project_override = true
  billing_project       = "u2i-bootstrap"
}

# Get organization outputs
data "terraform_remote_state" "organization" {
  backend = "gcs"
  config = {
    bucket = "u2i-tfstate"
    prefix = "organization"
  }
}

# Shared GKE Infrastructure Projects
resource "google_project" "gke_projects" {
  for_each = {
    "u2i-gke-prod"    = "Production GKE cluster project"
    "u2i-gke-nonprod" = "Non-production GKE cluster project"
    "u2i-gke-network" = "Shared networking project"
  }
  
  name            = each.key
  project_id      = each.key
  billing_account = var.billing_account
  folder_id       = data.terraform_remote_state.organization.outputs.folder_structure.compliant
  
  labels = {
    environment         = each.key == "u2i-gke-prod" ? "production" : (each.key == "u2i-gke-nonprod" ? "non-production" : "shared")
    purpose            = "shared-gke"
    compliance         = "iso27001-soc2-gdpr"
    data_residency     = "eu"
    region            = "belgium"
    gdpr_compliant    = "true"
  }
}

# Enable required APIs
resource "google_project_service" "gke_apis" {
  for_each = {
    for pair in setproduct(keys(google_project.gke_projects), [
      "container.googleapis.com",
      "compute.googleapis.com",
      "logging.googleapis.com",
      "monitoring.googleapis.com"
    ]) : "${pair[0]}-${pair[1]}" => {
      project = pair[0]
      service = pair[1]
    }
  }
  
  project = google_project.gke_projects[each.value.project].project_id
  service = each.value.service
  
  disable_on_destroy = false
}

# Enable Shared VPC on network project
resource "google_compute_shared_vpc_host_project" "network_host" {
  project = google_project.gke_projects["u2i-gke-network"].project_id
  
  depends_on = [google_project_service.gke_apis]
}

# Attach service projects to shared VPC
resource "google_compute_shared_vpc_service_project" "prod_service" {
  host_project    = google_project.gke_projects["u2i-gke-network"].project_id
  service_project = google_project.gke_projects["u2i-gke-prod"].project_id
  
  depends_on = [google_compute_shared_vpc_host_project.network_host]
}

resource "google_compute_shared_vpc_service_project" "nonprod_service" {
  host_project    = google_project.gke_projects["u2i-gke-network"].project_id
  service_project = google_project.gke_projects["u2i-gke-nonprod"].project_id
  
  depends_on = [google_compute_shared_vpc_host_project.network_host]
}

# Shared VPC Network
resource "google_compute_network" "gke_shared_network" {
  project                 = google_project.gke_projects["u2i-gke-network"].project_id
  name                    = "gke-shared-vpc"
  auto_create_subnetworks = false
  description            = "Shared VPC for compliant GKE clusters - Belgium"
  
  depends_on = [google_compute_shared_vpc_host_project.network_host]
}

# Production subnet
resource "google_compute_subnetwork" "prod_subnet" {
  project       = google_project.gke_projects["u2i-gke-network"].project_id
  name          = "gke-prod-subnet"
  network       = google_compute_network.gke_shared_network.name
  ip_cidr_range = "10.0.0.0/20"
  region        = var.primary_region
  
  secondary_ip_range {
    range_name    = "prod-pods"
    ip_cidr_range = "10.16.0.0/14"
  }
  
  secondary_ip_range {
    range_name    = "prod-services"
    ip_cidr_range = "10.20.0.0/16"
  }
  
  private_ip_google_access = true
}

# Non-production subnet
resource "google_compute_subnetwork" "nonprod_subnet" {
  project       = google_project.gke_projects["u2i-gke-network"].project_id
  name          = "gke-nonprod-subnet"
  network       = google_compute_network.gke_shared_network.name
  ip_cidr_range = "10.1.0.0/20"
  region        = var.primary_region
  
  secondary_ip_range {
    range_name    = "nonprod-pods"
    ip_cidr_range = "10.24.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "nonprod-services"
    ip_cidr_range = "10.25.0.0/16"
  }
  
  private_ip_google_access = true
}

# Cloud Router for NAT
resource "google_compute_router" "gke_router" {
  project = google_project.gke_projects["u2i-gke-network"].project_id
  name    = "gke-cloud-router"
  region  = var.primary_region
  network = google_compute_network.gke_shared_network.id
}

# Cloud NAT for outbound access
resource "google_compute_router_nat" "gke_nat" {
  project = google_project.gke_projects["u2i-gke-network"].project_id
  name    = "gke-nat"
  router  = google_compute_router.gke_router.name
  region  = var.primary_region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# IAM permissions for GKE service accounts to use Shared VPC subnets
resource "google_compute_subnetwork_iam_member" "prod_gke_subnet_user" {
  project    = google_project.gke_projects["u2i-gke-network"].project_id
  region     = var.primary_region
  subnetwork = google_compute_subnetwork.prod_subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${google_project.gke_projects["u2i-gke-prod"].number}@container-engine-robot.iam.gserviceaccount.com"
  
  depends_on = [google_compute_subnetwork.prod_subnet]
}

resource "google_compute_subnetwork_iam_member" "nonprod_gke_subnet_user" {
  project    = google_project.gke_projects["u2i-gke-network"].project_id
  region     = var.primary_region
  subnetwork = google_compute_subnetwork.nonprod_subnet.name
  role       = "roles/compute.networkUser"
  member     = "serviceAccount:service-${google_project.gke_projects["u2i-gke-nonprod"].number}@container-engine-robot.iam.gserviceaccount.com"
  
  depends_on = [google_compute_subnetwork.nonprod_subnet]
}

# Additional IAM permissions for GKE service accounts on host project
resource "google_project_iam_member" "prod_gke_host_service_agent" {
  project = google_project.gke_projects["u2i-gke-network"].project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${google_project.gke_projects["u2i-gke-prod"].number}@container-engine-robot.iam.gserviceaccount.com"
  
  depends_on = [google_compute_shared_vpc_service_project.prod_service]
}

resource "google_project_iam_member" "nonprod_gke_host_service_agent" {
  project = google_project.gke_projects["u2i-gke-network"].project_id
  role    = "roles/container.hostServiceAgentUser"
  member  = "serviceAccount:service-${google_project.gke_projects["u2i-gke-nonprod"].number}@container-engine-robot.iam.gserviceaccount.com"
  
  depends_on = [google_compute_shared_vpc_service_project.nonprod_service]
}

# Production GKE Autopilot Cluster
resource "google_container_cluster" "prod_autopilot" {
  project  = google_project.gke_projects["u2i-gke-prod"].project_id
  name     = "prod-autopilot"
  location = var.primary_region
  
  enable_autopilot = true
  
  network    = google_compute_network.gke_shared_network.id
  subnetwork = google_compute_subnetwork.prod_subnet.id
  
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block = "172.16.0.0/28"
  }
  
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.0/8"
      display_name = "Private networks"
    }
  }
  
  ip_allocation_policy {
    cluster_secondary_range_name  = "prod-pods"
    services_secondary_range_name = "prod-services"
  }
  
  workload_identity_config {
    workload_pool = "${google_project.gke_projects["u2i-gke-prod"].project_id}.svc.id.goog"
  }
  
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  resource_labels = {
    environment         = "production"
    compliance_framework = "iso27001-soc2-gdpr"
    data_residency     = "eu"
    region            = "belgium"
    gdpr_compliant    = "true"
  }
  
  deletion_protection = false
  
  depends_on = [google_project_service.gke_apis]
}

# Non-Production GKE Autopilot Cluster
resource "google_container_cluster" "nonprod_autopilot" {
  project  = google_project.gke_projects["u2i-gke-nonprod"].project_id
  name     = "nonprod-autopilot"
  location = var.primary_region
  
  enable_autopilot = true
  
  network    = google_compute_network.gke_shared_network.id
  subnetwork = google_compute_subnetwork.nonprod_subnet.id
  
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false  # Allow public API for development
    master_ipv4_cidr_block = "172.16.1.0/28"
  }
  
  ip_allocation_policy {
    cluster_secondary_range_name  = "nonprod-pods"
    services_secondary_range_name = "nonprod-services"
  }
  
  workload_identity_config {
    workload_pool = "${google_project.gke_projects["u2i-gke-nonprod"].project_id}.svc.id.goog"
  }
  
  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }
  
  resource_labels = {
    environment         = "non-production"
    compliance_framework = "iso27001-soc2-gdpr"
    data_residency     = "eu"
    region            = "belgium"
    gdpr_compliant    = "true"
  }
  
  deletion_protection = false
  
  depends_on = [google_project_service.gke_apis]
}

# Kubernetes provider configuration for cluster management
provider "kubernetes" {
  alias = "nonprod"
  host  = "https://${google_container_cluster.nonprod_autopilot.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.nonprod_autopilot.master_auth[0].cluster_ca_certificate,
  )
}

provider "kubernetes" {
  alias = "prod"
  host  = "https://${google_container_cluster.prod_autopilot.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    google_container_cluster.prod_autopilot.master_auth[0].cluster_ca_certificate,
  )
}

data "google_client_config" "default" {}

# Tenant namespaces registry
variable "tenant_namespaces" {
  description = "Map of tenant namespaces to create on both clusters"
  type = map(object({
    team_email        = string
    cost_center      = string
    billing_project  = string
    compliance_level = string
  }))
  default = {
    webapp-team = {
      team_email       = "webapp-team@u2i.com"
      cost_center     = "webapp-team"
      billing_project = "u2i-tenant-webapp"
      compliance_level = "iso27001-soc2-gdpr"
    }
  }
}

# Create tenant namespaces on nonprod cluster
resource "kubernetes_namespace" "tenant_namespaces_nonprod" {
  provider = kubernetes.nonprod
  for_each = var.tenant_namespaces
  
  metadata {
    name = each.key
    
    labels = {
      tenant             = each.key
      team              = each.key
      managed-by        = "platform-team"
      environment       = "non-production"
      compliance        = each.value.compliance_level
      data-residency    = "eu"
      gdpr-compliant   = "true"
      cost-center      = each.value.cost_center
      billing-project  = each.value.billing_project
      
      # Pod Security Standards
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    
    annotations = {
      team-email                = each.value.team_email
      on-call                  = "${each.key}-oncall@u2i.com"
      tenant-project           = each.value.billing_project
      created-by              = "platform-team"
      compliance-review-date  = "2025-06-16"
      gdpr-data-controller    = each.value.team_email
      network-policy          = "enforced"
      resource-quota          = "enforced"
    }
  }
  
  depends_on = [google_container_cluster.nonprod_autopilot]
}

# Create tenant namespaces on prod cluster  
resource "kubernetes_namespace" "tenant_namespaces_prod" {
  provider = kubernetes.prod
  for_each = var.tenant_namespaces
  
  metadata {
    name = each.key
    
    labels = {
      tenant             = each.key
      team              = each.key
      managed-by        = "platform-team"
      environment       = "production"
      compliance        = each.value.compliance_level
      data-residency    = "eu"
      gdpr-compliant   = "true"
      cost-center      = each.value.cost_center
      billing-project  = each.value.billing_project
      
      # Pod Security Standards
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
    
    annotations = {
      team-email                = each.value.team_email
      on-call                  = "${each.key}-oncall@u2i.com"
      tenant-project           = each.value.billing_project
      created-by              = "platform-team"
      compliance-review-date  = "2025-06-16"
      gdpr-data-controller    = each.value.team_email
      network-policy          = "enforced"
      resource-quota          = "enforced"
    }
  }
  
  depends_on = [google_container_cluster.prod_autopilot]
}

# Data sources for existing Cloud Deploy service accounts from tenant projects
data "google_service_account" "tenant_cloud_deploy_sas" {
  for_each = var.tenant_namespaces
  
  account_id = "cloud-deploy-sa"
  project    = each.value.billing_project
}

# Create cluster roles for Cloud Deploy service accounts
resource "kubernetes_cluster_role" "cloud_deploy_cluster_role" {
  provider = kubernetes.nonprod
  
  metadata {
    name = "cloud-deploy-cluster-role"
  }
  
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["resourcequotas", "limitranges"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  depends_on = [google_container_cluster.nonprod_autopilot]
}

resource "kubernetes_cluster_role" "cloud_deploy_cluster_role_prod" {
  provider = kubernetes.prod
  
  metadata {
    name = "cloud-deploy-cluster-role"
  }
  
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  rule {
    api_groups = [""]
    resources  = ["resourcequotas", "limitranges"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  
  depends_on = [google_container_cluster.prod_autopilot]
}

# Bind Cloud Deploy service accounts to cluster roles
resource "kubernetes_cluster_role_binding" "cloud_deploy_cluster_binding_nonprod" {
  provider = kubernetes.nonprod
  for_each = var.tenant_namespaces
  
  metadata {
    name = "cloud-deploy-${each.key}-binding"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cloud_deploy_cluster_role.metadata[0].name
  }
  
  subject {
    kind      = "User"
    name      = data.google_service_account.tenant_cloud_deploy_sas[each.key].email
    api_group = "rbac.authorization.k8s.io"
  }
  
  depends_on = [kubernetes_cluster_role.cloud_deploy_cluster_role]
}

resource "kubernetes_cluster_role_binding" "cloud_deploy_cluster_binding_prod" {
  provider = kubernetes.prod
  for_each = var.tenant_namespaces
  
  metadata {
    name = "cloud-deploy-${each.key}-binding"
  }
  
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.cloud_deploy_cluster_role_prod.metadata[0].name
  }
  
  subject {
    kind      = "User"
    name      = data.google_service_account.tenant_cloud_deploy_sas[each.key].email
    api_group = "rbac.authorization.k8s.io"
  }
  
  depends_on = [kubernetes_cluster_role.cloud_deploy_cluster_role_prod]
}

# Grant GKE node service accounts permission to pull images from tenant Artifact Registry repositories
resource "google_project_iam_member" "gke_nonprod_artifact_registry_reader" {
  for_each = var.tenant_namespaces
  
  project = each.value.billing_project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:service-${google_project.gke_projects["u2i-gke-nonprod"].number}@container-engine-robot.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "gke_prod_artifact_registry_reader" {
  for_each = var.tenant_namespaces
  
  project = each.value.billing_project
  role    = "roles/artifactregistry.reader" 
  member  = "serviceAccount:service-${google_project.gke_projects["u2i-gke-prod"].number}@container-engine-robot.iam.gserviceaccount.com"
}