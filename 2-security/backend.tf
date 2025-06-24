# Backend configuration for security phase
terraform {
  backend "gcs" {
    bucket = "u2i-tfstate"
    prefix = "security"
  }
}