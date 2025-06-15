output "bootstrap_project_id" {
  value = google_project.bootstrap.project_id
}

output "terraform_sa_email" {
  value       = google_service_account.terraform_bootstrap.email
  description = "Bootstrap service account (read-only + state access)"
}

output "tfstate_bucket" {
  value = google_storage_bucket.tfstate.name
}