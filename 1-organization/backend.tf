terraform {
  backend "gcs" {
    bucket = "u2i-tfstate"
    prefix = "organization"
  }
}