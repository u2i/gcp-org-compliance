terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20"
    }
  }

  backend "gcs" {
    bucket = "u2i-tfstate"
    prefix = "shared-gke-resources"
  }
}

# Get shared GKE outputs
data "terraform_remote_state" "shared_gke" {
  backend = "gcs"
  config = {
    bucket = "u2i-tfstate"
    prefix = "shared-gke"
  }
}

# Get organization outputs
data "terraform_remote_state" "organization" {
  backend = "gcs"
  config = {
    bucket = "u2i-tfstate"
    prefix = "organization"
  }
}

# Configure the Google Provider
provider "google" {
  user_project_override = true
  billing_project       = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-nonprod"].project_id
}

provider "google-beta" {
  user_project_override = true
  billing_project       = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-nonprod"].project_id
}

# Configure Kubernetes providers for each cluster
data "google_container_cluster" "nonprod" {
  name     = "nonprod-autopilot"
  location = var.primary_region
  project  = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-nonprod"].project_id
}

data "google_container_cluster" "prod" {
  name     = "prod-autopilot"
  location = var.primary_region
  project  = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-prod"].project_id
}

provider "kubernetes" {
  alias = "nonprod"

  host                   = "https://${data.google_container_cluster.nonprod.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.nonprod.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  alias = "prod"

  host                   = "https://${data.google_container_cluster.prod.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.prod.master_auth[0].cluster_ca_certificate)
}

data "google_client_config" "default" {}