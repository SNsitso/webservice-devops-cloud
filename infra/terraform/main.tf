# =====================
# MAIN
# Définition de toutes les ressources GCP
# =====================

# ----------------------
# VPC Network (existant — réseau "default" GCP)
# Non géré par Terraform, référencé via data source
# ----------------------
data "google_compute_network" "vpc" {
  name    = var.network_name
  project = var.project_id
}

# ----------------------
# GKE Autopilot Cluster
# ----------------------
resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  deletion_protection = false

  enable_autopilot = true

  network    = data.google_compute_network.vpc.id
  subnetwork = data.google_compute_network.vpc.name

  ip_allocation_policy {}

  # Noeuds publics — correspond a la configuration reelle du cluster
  private_cluster_config {
    enable_private_nodes    = false
    enable_private_endpoint = false
  }

  release_channel {
    channel = "REGULAR"
  }
}

# ----------------------
# Cloud SQL - MySQL 8.4
# ----------------------
resource "google_sql_database_instance" "mysql" {
  name             = var.db_instance_name
  database_version = "MYSQL_8_4"
  region           = var.region
  project          = var.project_id

  deletion_protection = false

  settings {
    tier            = var.db_tier
    edition         = "ENTERPRISE"
    disk_autoresize = true

    backup_configuration {
      enabled            = true
      binary_log_enabled = true
      start_time         = "02:00"
    }

    ip_configuration {
      ipv4_enabled    = true
      private_network = data.google_compute_network.vpc.id
    }

    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    database_flags {
      name  = "character_set_server"
      value = "utf8mb4"
    }
  }
}

resource "google_sql_database" "wordpress" {
  name     = var.db_name
  instance = google_sql_database_instance.mysql.name
  project  = var.project_id
}

resource "google_sql_user" "wordpress" {
  name     = var.db_user
  instance = google_sql_database_instance.mysql.name
  password = var.db_password
  project  = var.project_id
}
