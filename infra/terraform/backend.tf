# =====================
# BACKEND
# Stockage du state Terraform dans GCS
# Permet de versionner et partager l'état de l'infrastructure
# =====================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "webservice-devops-terraform-state"
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
