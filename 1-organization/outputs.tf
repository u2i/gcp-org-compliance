output "folder_structure" {
  value = {
    legacy     = module.org_structure.folder_ids["legacy-systems"]
    migration  = module.org_structure.folder_ids["migration-in-progress"]
    compliant  = module.org_structure.folder_ids["compliant-systems"]
  }
}

output "migration_instructions" {
  value = <<-EOT
    Next Steps:
    1. Move all existing projects to legacy folder: ${module.org_structure.folder_ids["legacy-systems"]}
       Run: ./scripts/move-projects-to-legacy.sh ${module.org_structure.folder_ids["legacy-systems"]}
    
    2. Assess each project for compliance:
       Run: ./scripts/assess-project-compliance.sh PROJECT_ID
    
    3. Create migration plan for each project
    
    4. Move projects through migration folder as they're updated
  EOT
}

# GitOps outputs
output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Workload Identity Provider for GitHub Actions"
}

output "terraform_organization_sa" {
  value       = google_service_account.terraform_organization.email
  description = "Organization Terraform service account (read-only + PAM elevation)"
}

output "terraform_security_sa" {
  value       = google_service_account.terraform_security.email
  description = "Security Terraform service account (read-only + PAM elevation)"
}


output "github_actions_setup" {
  value = {
    workload_identity_provider = google_iam_workload_identity_pool_provider.github.name
    organization_sa           = google_service_account.terraform_organization.email
    security_sa              = google_service_account.terraform_security.email
    repository               = "u2i/gcp-org-compliance"
  }
  description = "GitHub Actions configuration values"
}

output "dns_configuration" {
  description = "DNS configuration for u2i.dev domain"
  value = {
    zone_name    = google_dns_managed_zone.u2i_dev.name
    dns_name     = google_dns_managed_zone.u2i_dev.dns_name
    name_servers = google_dns_managed_zone.u2i_dev.name_servers
    project_id   = google_project.dns_project.project_id
    registrar_setup = <<-EOT
      Configure these nameservers at your domain registrar:
      ${join("\n      ", google_dns_managed_zone.u2i_dev.name_servers)}
      
      Note: Application-specific DNS records are managed in their respective projects.
      This ensures proper access control and allows teams to manage their own DNS.
    EOT
  }
}