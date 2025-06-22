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

# Output approval system configuration for tenant projects
output "approval_system" {
  description = "Centralized approval system configuration"
  value = {
    function_url    = google_cloudfunctions2_function.approval_handler.service_config[0].uri
    approval_bucket = google_storage_bucket.approval_storage.name
    
    # For tenant workflows to reference
    slack_button_values = {
      webapp_team = "approve:webapp-team-infrastructure:{run_id}"
      data_team   = "approve:data-team-infrastructure:{run_id}" 
      org_level   = "approve:gcp-org-compliance:{run_id}"
    }
    
    # Instructions for Slack app configuration
    slack_configuration = {
      interactive_components_url = google_cloudfunctions2_function.approval_handler.service_config[0].uri
      required_scopes = [
        "chat:write",
        "commands", 
        "users:read"
      ]
    }
  }
}