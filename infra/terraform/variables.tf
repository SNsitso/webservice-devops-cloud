# =====================
# VARIABLES — valeurs alignées sur l'infrastructure réelle
# =====================

variable "project_id" {
  description = "ID du projet GCP"
  type        = string
  default     = "webservice-devops"
}

variable "region" {
  description = "Région GCP (Cloud SQL)"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "Zone GCP du cluster (zonal : frais de gestion couverts par le free tier)"
  type        = string
  default     = "europe-west1-b"
}

variable "network_name" {
  description = "Nom du réseau VPC (réseau existant dans GCP)"
  type        = string
  default     = "default"
}

# ---------- GKE ----------

variable "cluster_name" {
  description = "Nom du cluster GKE (nom hérité de la création console, immuable)"
  type        = string
  default     = "cluster-1"
}

variable "node_machine_type" {
  description = "Type de machine des nœuds"
  type        = string
  default     = "e2-small"
}

variable "node_count" {
  description = "Nombre de nœuds du pool (0 = pause du cluster, 2 = normal)"
  type        = number
  default     = 2
}

# ---------- Cloud SQL ----------

variable "db_instance_name" {
  description = "Nom de l'instance Cloud SQL"
  type        = string
  default     = "wordpress-db"
}

variable "db_tier" {
  description = "Taille de l'instance Cloud SQL"
  type        = string
  default     = "db-f1-micro"
}

variable "db_activation_policy" {
  description = "ALWAYS = instance démarrée, NEVER = stoppée (pause coûts)"
  type        = string
  default     = "ALWAYS"
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
  description = "Mot de passe de la base (= valeur dans Secret Manager wordpress-db-password)"
  type        = string
  sensitive   = true
}
