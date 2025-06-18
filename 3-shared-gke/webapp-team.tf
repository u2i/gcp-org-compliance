# WebApp Team GKE Resources
# This file manages cross-project resources that the webapp team cannot manage themselves

locals {
  webapp_project_id = "u2i-tenant-webapp"
  webapp_team_name  = "webapp-team"
}

# Create tenant namespace in shared clusters
resource "kubernetes_namespace" "webapp_nonprod" {
  provider = kubernetes.nonprod

  metadata {
    name = local.webapp_team_name

    labels = {
      "tenant"                             = local.webapp_team_name
      "environment"                        = "non-production"
      "compliance"                         = "iso27001-soc2-gdpr"
      "data-residency"                     = "eu"
      "gdpr-compliant"                     = "true"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }

    annotations = {
      "tenant-project" = local.webapp_project_id
      "created-by"     = "terraform"
      "managed-by"     = "shared-gke-resources"
    }
  }
}

resource "kubernetes_namespace" "webapp_prod" {
  provider = kubernetes.prod

  metadata {
    name = local.webapp_team_name

    labels = {
      "tenant"                             = local.webapp_team_name
      "environment"                        = "production"
      "compliance"                         = "iso27001-soc2-gdpr"
      "data-residency"                     = "eu"
      "gdpr-compliant"                     = "true"
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }

    annotations = {
      "tenant-project" = local.webapp_project_id
      "created-by"     = "terraform"
      "managed-by"     = "shared-gke-resources"
    }
  }
}

# Resource quota for tenant namespace
resource "kubernetes_resource_quota" "webapp_nonprod_quota" {
  provider = kubernetes.nonprod

  metadata {
    name      = "${local.webapp_team_name}-quota"
    namespace = kubernetes_namespace.webapp_nonprod.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "2"
      "requests.memory" = "4Gi"
      "limits.cpu"      = "4"
      "limits.memory"   = "8Gi"
      "pods"            = "10"
      "services"        = "5"
    }
  }
}

resource "kubernetes_resource_quota" "webapp_prod_quota" {
  provider = kubernetes.prod

  metadata {
    name      = "${local.webapp_team_name}-quota"
    namespace = kubernetes_namespace.webapp_prod.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = "4"
      "requests.memory" = "8Gi"
      "limits.cpu"      = "8"
      "limits.memory"   = "16Gi"
      "pods"            = "20"
      "services"        = "10"
    }
  }
}

# Network policies for tenant isolation
resource "kubernetes_network_policy" "webapp_isolation_nonprod" {
  provider = kubernetes.nonprod

  metadata {
    name      = "${local.webapp_team_name}-isolation"
    namespace = kubernetes_namespace.webapp_nonprod.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from same namespace and ingress controllers
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.webapp_nonprod.metadata[0].name
          }
        }
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "gke-system"
          }
        }
      }
    }

    # Allow egress to DNS, same namespace, and external (for business logic)
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.webapp_nonprod.metadata[0].name
          }
        }
      }
    }

    # Allow egress to external services (Internet)
    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }

    egress {
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }
  }
}

resource "kubernetes_network_policy" "webapp_isolation_prod" {
  provider = kubernetes.prod

  metadata {
    name      = "${local.webapp_team_name}-isolation"
    namespace = kubernetes_namespace.webapp_prod.metadata[0].name
  }

  spec {
    pod_selector {}

    policy_types = ["Ingress", "Egress"]

    # Allow ingress from same namespace and ingress controllers
    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.webapp_prod.metadata[0].name
          }
        }
      }
    }

    ingress {
      from {
        namespace_selector {
          match_labels = {
            name = "gke-system"
          }
        }
      }
    }

    # Allow egress to DNS, same namespace, and external
    egress {
      to {
        namespace_selector {
          match_labels = {
            name = "kube-system"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            name = kubernetes_namespace.webapp_prod.metadata[0].name
          }
        }
      }
    }

    # Allow egress to external services (Internet)
    egress {
      ports {
        port     = "443"
        protocol = "TCP"
      }
    }

    egress {
      ports {
        port     = "80"
        protocol = "TCP"
      }
    }
  }
}

# Grant Cloud Deploy service account permissions on GKE projects
resource "google_project_iam_member" "webapp_cloud_deploy_nonprod_access" {
  project = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-nonprod"].project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:cloud-deploy-sa@${local.webapp_project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "webapp_cloud_deploy_prod_access" {
  project = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-prod"].project_id
  role    = "roles/container.developer"
  member  = "serviceAccount:cloud-deploy-sa@${local.webapp_project_id}.iam.gserviceaccount.com"
}

# RBAC for tenant namespace access
resource "kubernetes_role" "webapp_namespace_admin_nonprod" {
  provider = kubernetes.nonprod

  metadata {
    name      = "${local.webapp_team_name}-admin"
    namespace = kubernetes_namespace.webapp_nonprod.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "webapp_namespace_admin_nonprod" {
  provider = kubernetes.nonprod

  metadata {
    name      = "${local.webapp_team_name}-admin-binding"
    namespace = kubernetes_namespace.webapp_nonprod.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.webapp_namespace_admin_nonprod.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "cloud-deploy-sa"
    namespace = "default"
  }

  # Add any webapp team members who need direct kubectl access
  # subject {
  #   kind      = "User"
  #   name      = "user@example.com"
  #   api_group = "rbac.authorization.k8s.io"
  # }
}

resource "kubernetes_role" "webapp_namespace_admin_prod" {
  provider = kubernetes.prod

  metadata {
    name      = "${local.webapp_team_name}-admin"
    namespace = kubernetes_namespace.webapp_prod.metadata[0].name
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "webapp_namespace_admin_prod" {
  provider = kubernetes.prod

  metadata {
    name      = "${local.webapp_team_name}-admin-binding"
    namespace = kubernetes_namespace.webapp_prod.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.webapp_namespace_admin_prod.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "cloud-deploy-sa"
    namespace = "default"
  }
}