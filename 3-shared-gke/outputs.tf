output "tenant_namespaces" {
  description = "Tenant namespaces managed by this configuration"
  value = {
    webapp_team = {
      message = "Namespaces and permissions configured in tenant-namespaces/webapp-team.tf"
      nonprod = {
        namespace = "webapp-team"
        project   = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-nonprod"].project_id
      }
      prod = {
        namespace = "webapp-team"
        project   = data.terraform_remote_state.shared_gke.outputs.projects_created["u2i-gke-prod"].project_id
      }
    }
  }
}

output "managed_resources" {
  description = "Summary of resources managed for each tenant"
  value = {
    webapp_team = {
      namespaces      = "Created in both nonprod and prod clusters"
      resource_quotas = "Applied with CPU/memory limits"
      network_policies = "Namespace isolation enforced"
      iam_bindings    = "Cloud Deploy SA granted container.developer role"
      rbac           = "Namespace-scoped roles and bindings"
    }
  }
}