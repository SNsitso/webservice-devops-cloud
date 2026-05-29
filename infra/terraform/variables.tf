# =====================
# VARIABLES
# Toutes les valeurs configurables de l'infrastructure
# =====================

variable "project_id" {
  description = "ID du projet GCP"
  type        = string
  default     = "webservice-devops"
}

variable "region" {
  description = "Région GCP"
  type        = string
  default     = "europe-west1"
}

variable "cluster_name" {
  description = "Nom du cluster GKE"
  type        = string
  default     = "wordpress-autopilot-cluster-1"
}

variable "network_name" {
  description = "Nom du réseau VPC (réseau existant dans GCP)"
  type        = string
  default     = "default"
}

variable "db_instance_name" {
  description = "Nom de l'instance Cloud SQL"
  type        = string
  default     = "wordpress-db"
}

variable "db_tier" {
  description = "Taille de l'instance Cloud SQL"
  type        = string
  default     = "db-g1-small"
}

variable "db_name" {
  description = "Nom de la base de données"
  type        = string
  default     = "wordpress"
}

variable "db_user" {
  description = "Utilisateur de la base de données"
  type        = string
  default     = "wordpress"
}

variable "db_password" {
  description = "Mot de passe de la base de données"
  type        = string
  sensitive   = true
}
