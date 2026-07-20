# =====================
# OUTPUTS
# =====================

output "gke_cluster_name" {
  description = "Nom du cluster GKE"
  value       = google_container_cluster.gke.name
}

output "gke_zone" {
  description = "Zone du cluster GKE"
  value       = var.zone
}

output "cloudsql_private_ip" {
  description = "IP privée de l'instance Cloud SQL (à reporter dans values-gke.yaml)"
  value       = google_sql_database_instance.mysql.private_ip_address
}

output "cloudsql_instance_name" {
  description = "Nom de l'instance Cloud SQL"
  value       = google_sql_database_instance.mysql.name
}

output "eso_service_account_email" {
  description = "GSA utilisé par External Secrets Operator (Workload Identity)"
  value       = google_service_account.eso.email
}

output "vpc_name" {
  description = "Nom du VPC utilisé"
  value       = data.google_compute_network.vpc.name
}
