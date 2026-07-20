# =====================
# MAIN — infrastructure GCP réelle (réalignée après création console)
# Cluster GKE Standard zonal + Cloud SQL MySQL 8.0 + secrets + IAM ESO
# =====================

# ----------------------
# VPC (réseau "default" existant, non géré — data source)
# ----------------------
data "google_compute_network" "vpc" {
  name    = var.network_name
  project = var.project_id
}

# ----------------------
# Cluster GKE Standard (zonal — free tier sur les frais de gestion)
# Le node pool est géré par une ressource dédiée ci-dessous.
# ----------------------
resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.zone
  project  = var.project_id

  deletion_protection = false

  network    = data.google_compute_network.vpc.id
  subnetwork = data.google_compute_network.vpc.name

  ip_allocation_policy {}

  release_channel {
    channel = "REGULAR"
  }

  # Fédération d'identités pods ↔ GCP (prérequis External Secrets Operator)
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Le provider refuse "KUBE_DNS" en input alors que l'API le retourne :
  # on ignore ce bloc système (défaut GKE, jamais modifié).
  lifecycle {
    ignore_changes = [dns_config]
  }
}

# ----------------------
# Node pool : e2-small Spot (coût ~÷3, préemptions absorbées par le GitOps)
# node_count est une variable : la "pause" du cluster = node_count 0
# ----------------------
resource "google_container_node_pool" "default_pool" {
  name     = "default-pool"
  cluster  = google_container_cluster.gke.name
  location = var.zone
  project  = var.project_id

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    spot         = true
    disk_size_gb = 30
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    # Scopes par défaut GKE ("Allow default access")
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]

    # Aligné sur la réalité (secure boot non coché à la création console)
    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = false
    }
  }

  # Google ajoute d'office quantité de sous-blocs (advanced_machine_features,
  # placement_policy, etc.) qui, si absents du code, seraient marqués
  # "forces replacement" et détruiraient le node pool. On ignore ces défauts
  # système : notre code ne pilote que ce qui compte (type de machine, Spot,
  # disque, sécurité de base).
  lifecycle {
    ignore_changes = [
      node_config[0].advanced_machine_features,
      node_config[0].ephemeral_storage_local_ssd_config,
      node_config[0].kubelet_config,
      node_config[0].workload_metadata_config,
      node_config[0].labels,
      node_config[0].metadata,
      node_config[0].tags,
      node_config[0].resource_labels,
      node_config[0].service_account,
      placement_policy,
      queued_provisioning,
      upgrade_settings,
      management,
      network_config,
      initial_node_count,
      node_locations,
    ]
  }
}

# ----------------------
# Cloud SQL — MySQL 8.0
# (8.4 écarté : mysql_native_password retiré, incompatible avec le client
# MariaDB embarqué par l'image Bitnami — voir CULTURE.md, saga DB)
# activation_policy en variable : NEVER = instance stoppée (pause coûts)
# ----------------------
resource "google_sql_database_instance" "mysql" {
  name             = var.db_instance_name
  database_version = "MYSQL_8_0"
  region           = var.region
  project          = var.project_id

  deletion_protection = false

  settings {
    tier              = var.db_tier
    edition           = "ENTERPRISE"
    activation_policy = var.db_activation_policy
    disk_type         = "PD_HDD"
    disk_size         = 10
    # false : plafond de facturation dur (lab). Le prochain apply désactivera
    # l'autoresize activé par défaut à la création console.
    disk_autoresize = false

    backup_configuration {
      enabled = false
    }

    # Flag hérité de la création console (auth IAM Cloud SQL — non utilisée
    # par WordPress mais on le préserve pour ne pas re-provisionner)
    database_flags {
      name  = "cloudsql_iam_authentication"
      value = "on"
    }

    ip_configuration {
      # IP privée UNIQUEMENT (peering PSA) — jamais exposée sur Internet
      ipv4_enabled       = false
      private_network    = data.google_compute_network.vpc.id
      allocated_ip_range = "default-ip-range-1778166503389"
    }

    # Déclaré explicitement : le provider Google refuse un maintenance_window
    # vide au PATCH (day=0 invalide à l'update). Dimanche 4h, canal canary.
    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "canary"
    }
  }

  # Blocs ajoutés d'office par Google (politique de mots de passe, dataplex,
  # PSC) — on ne les pilote pas.
  lifecycle {
    ignore_changes = [
      settings[0].password_validation_policy,
      settings[0].enable_dataplex_integration,
      settings[0].ip_configuration[0].psc_config,
    ]
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

# ----------------------
# Secret Manager — conteneurs de secrets UNIQUEMENT
# Les VERSIONS (valeurs) ne sont pas gérées par Terraform : elles
# finiraient en clair dans le state. Ajout des valeurs via gcloud/console.
# ----------------------
resource "google_secret_manager_secret" "wordpress_db_password" {
  secret_id = "wordpress-db-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "wordpress_admin_password" {
  secret_id = "wordpress-admin-password"
  project   = var.project_id

  replication {
    auto {}
  }
}

# ----------------------
# IAM — External Secrets Operator (Workload Identity)
# GSA + rôle de lecture des secrets + binding KSA↔GSA
# ----------------------
resource "google_service_account" "eso" {
  account_id   = "eso-sa"
  display_name = "External Secrets Operator"
  project      = var.project_id
}

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# Le KSA external-secrets/external-secrets peut AGIR COMME le GSA eso-sa
resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}
