# =====================
# OUTPUTS
# Valeurs exportées après terraform apply
# Utilisées par le pipeline GitLab CI pour déployer
# =====================

output "gke_cluster_name" {
  description = "Nom du cluster GKE"
  value       = google_container_cluster.gke.name
}

output "gke_cluster_endpoint" {
  description = "Endpoint du cluster GKE"
  value       = google_container_cluster.gke.endpoint
  sensitive   = true
}

output "gke_region" {
  description = "Région du cluster GKE"
  value       = var.region
}

output "cloudsql_private_ip" {
  description = "IP privée de l'instance Cloud SQL"
  value       = google_sql_database_instance.mysql.private_ip_address
}

output "cloudsql_public_ip" {
  description = "IP publique de l'instance Cloud SQL"
  value       = google_sql_database_instance.mysql.public_ip_address
}

output "cloudsql_instance_name" {
  description = "Nom de l'instance Cloud SQL"
  value       = google_sql_database_instance.mysql.name
}

output "vpc_name" {
  description = "Nom du VPC utilisé"
  value       = data.google_compute_network.vpc.name
}
