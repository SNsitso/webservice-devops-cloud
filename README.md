# WordPress on Kubernetes — Cloud & Local Deployment

A production-grade WordPress deployment project covering two deployment modes: a local Kubernetes cluster provisioned with Vagrant and kubeadm, and a cloud-native deployment on Google Kubernetes Engine (GKE) with a fully automated GitLab CI/CD pipeline.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [Project Structure](#project-structure)
- [Deployment Modes](#deployment-modes)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security](#security)
- [Infrastructure as Code](#infrastructure-as-code)
- [Prerequisites](#prerequisites)

---

## Overview

This project demonstrates end-to-end deployment automation of a WordPress application across two distinct environments:

- **Local**: A multi-node Kubernetes cluster created with Vagrant (VirtualBox) and bootstrapped with kubeadm, designed for offline development and testing without cloud dependencies.
- **Cloud**: A production-ready deployment on GKE Autopilot with a managed Cloud SQL MySQL 8.4 database, provisioned entirely through Terraform and deployed through a secured GitLab CI/CD pipeline.

The project applies DevOps principles throughout: infrastructure as code, automated security scanning, environment promotion (review → staging → production), and zero static credentials through OIDC federation.

---

## Architecture

### Cloud Architecture (GKE)

```
GitLab CI/CD (main branch)
        |
        | OIDC (Workload Identity Federation)
        v
   GCP Project: webservice-devops
        |
        |-- GKE Autopilot Cluster (europe-west1)
        |       |-- Namespace: review-*     (ephemeral per branch)
        |       |-- Namespace: staging
        |       |-- Namespace: wordpress    (production)
        |           |
        |           |-- WordPress Pod (bitnami/wordpress)
        |               |-- LoadBalancer Service
        |               |-- PersistentVolumeClaim (10Gi)
        |
        |-- Cloud SQL: MySQL 8.4 (ENTERPRISE, db-g1-small)
        |       |-- Private IP via VPC peering
        |       |-- IAM authentication enabled
        |       |-- Automated backups (daily at 02:00)
        |
        |-- GCS Bucket: Terraform remote state
        |
        |-- VPC: default network
```

### Local Architecture (Vagrant + kubeadm)

```
Host Machine (VirtualBox)
        |
        |-- controlplane  (1 VM)
        |-- node01        (1 VM)
        |-- node02        (1 VM)
            |
            |-- kubeadm bootstrap
            |-- WordPress Deployment (ClusterIP)
            |-- MySQL Deployment + PersistentVolume
            |-- Nginx Ingress Controller
            |-- MetalLB (LoadBalancer for bare-metal)
```

---

## Technology Stack

| Category | Technology |
|---|---|
| Container Orchestration | Kubernetes (GKE Autopilot, kubeadm) |
| Infrastructure as Code | Terraform >= 1.5 (Google provider ~> 5.0) |
| Package Manager | Helm 3 (custom chart) |
| Database | Cloud SQL MySQL 8.4 / MySQL 5.6 (local) |
| CI/CD | GitLab CI/CD (7 stages) |
| Authentication | OIDC Workload Identity Federation (no static keys) |
| Security Scanning | Trivy (image, config, secrets) |
| Application Image | bitnami/wordpress (non-root, port 8080) |
| Local Provisioning | Vagrant + VirtualBox + kubeadm |
| State Backend | Google Cloud Storage |
| Networking | GCP VPC, VPC Peering (Cloud SQL private IP) |
| Load Balancing | GKE LoadBalancer / MetalLB (local) |
| Ingress | Nginx Ingress Controller (local) / GKE native (cloud) |
| Monitoring | Prometheus + Grafana (local cluster) |
| Backup | Velero (local cluster) |

---

## Project Structure

```
wsdevops-Cloud/
|
|-- appli/                              # Application layer
|   |-- .gitlab-ci.yml                 # CI/CD pipeline (7 stages)
|   |-- .gitlab/
|   |   |-- agents/                    # GitLab Kubernetes agents config
|   |       |-- kubernetes-serge/
|   |       |-- agent-yousf/
|   |       |-- kubdernetes-mohamed/
|   |
|   |-- wordpress/                     # Helm chart (custom)
|       |-- Chart.yaml
|       |-- values.yaml                # Default values (local deployment)
|       |-- values-gke.yaml            # Override values (GKE deployment)
|       |-- templates/
|           |-- wordpress-deployment.yaml   # With strict securityContext
|           |-- wordpress-service.yaml
|           |-- ingress.yaml
|           |-- mysql-deployment.yaml       # Conditional (local only)
|           |-- mysql-service.yaml          # Conditional (local only)
|           |-- mysql-pvc.yaml              # Conditional (local only)
|           |-- mysql-secrets.yaml          # Conditional (local only)
|
|-- infra/                             # Infrastructure layer
    |-- terraform/                     # GCP provisioning
    |   |-- backend.tf                 # GCS remote state
    |   |-- main.tf                    # GKE cluster + Cloud SQL + VPC
    |   |-- variables.tf
    |   |-- outputs.tf
    |
    |-- kubeadm_kubernetes/            # Local cluster provisioning
        |-- Vagrantfile                # Multi-node VM definition
        |-- settings.yaml              # Cluster configuration
        |-- scripts/
        |   |-- common.sh              # Common setup (all nodes)
        |   |-- master.sh              # Control plane init
        |   |-- node.sh                # Worker node join
        |   |-- runner.sh              # GitLab runner setup
        |   |-- LoadBalancer.sh        # MetalLB setup
        |   |-- dashboard.sh           # Kubernetes dashboard
        |-- cert-manager/              # TLS certificate automation
        |-- monitoring/                # Prometheus + Grafana values
        |-- velero/                    # Backup configuration
```

---

## Deployment Modes

### Local Deployment (Vagrant + kubeadm)

Prerequisites: VirtualBox, Vagrant

```bash
cd infra/kubeadm_kubernetes
vagrant up
```

This provisions a control plane and two worker nodes, bootstraps the cluster with kubeadm, and installs MetalLB, Nginx Ingress, and cert-manager automatically through provisioning scripts.

Deploy WordPress locally:

```bash
helm upgrade --install wordpress appli/wordpress \
  -f appli/wordpress/values.yaml
```

### Cloud Deployment (GKE + Terraform)

Prerequisites: Terraform >= 1.5, gcloud CLI, kubectl, Helm 3

**Step 1 — Provision infrastructure**

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # fill in db_password
terraform init
terraform plan
terraform apply
```

This creates:
- GKE Autopilot cluster in `europe-west1`
- Cloud SQL MySQL 8.4 instance with private VPC connectivity
- Required IAM bindings for Workload Identity Federation

**Step 2 — Configure kubectl**

```bash
gcloud container clusters get-credentials wordpress-autopilot-cluster-1 \
  --region europe-west1 --project webservice-devops
```

**Step 3 — Deploy via pipeline**

Push to `main`. The GitLab CI/CD pipeline handles linting, security scanning, packaging, and deployment automatically.

**Tear down infrastructure**

```bash
terraform destroy
```

All resources are created with `deletion_protection = false` in Terraform to allow clean destruction.

---

## CI/CD Pipeline

The pipeline is defined in `appli/.gitlab-ci.yml` and triggers on every push to `main`.

```
main branch push
      |
      v
  [test]              helm lint + helm template dry-run
      |
      v
  [security_test]     trivy image scan     (CRITICAL CVEs with fix, blocking)
                      trivy config scan    (HIGH/CRITICAL K8s misconfigs, blocking)
                      trivy secret scan    (secrets in repository, blocking)
      |
      v
  [release]           helm package -> artifact (.tgz)
      |
      v
  [deploy_review]     helm install -> namespace review-* (ephemeral)
      |
      v
  [stop_review]       manual — helm uninstall + namespace deletion
      |
      v
  [deploy_staging]    helm upgrade --install -> namespace staging
      |
      v
  [deploy_prod]       manual gate — helm upgrade --install -> namespace wordpress
```

Authentication to GCP uses **OIDC Workload Identity Federation** — no service account keys are stored in GitLab. The CI job exchanges a short-lived GitLab ID token for a GCP access token at runtime.

**Required CI/CD variables** (Settings > CI/CD > Variables):

| Variable | Description |
|---|---|
| `GCP_PROJECT_ID` | GCP project ID |
| `GKE_CLUSTER_NAME` | GKE cluster name |
| `GKE_REGION` | GCP region |
| `WORDPRESS_DB_PASSWORD` | Database password (masked) |

**Required GitLab setting**: CI/CD configuration file path must be set to `appli/.gitlab-ci.yml`.

---

## Security

### Kubernetes Pod Security

The WordPress deployment enforces strict security constraints:

- Runs as non-root user (UID 1001, GID 1001) — bitnami/wordpress compliance
- `readOnlyRootFilesystem: true` — filesystem is immutable at runtime
- `allowPrivilegeEscalation: false`
- All Linux capabilities dropped (`drop: [ALL]`)
- `seccompProfile: RuntimeDefault`
- Write access only through explicitly declared `emptyDir` volumes (tmp, logs, apache config, php temp)

### CI/CD Security

- No static GCP credentials — OIDC token exchange only
- Database password injected at deploy time via `--set`, never stored in values files
- Three mandatory Trivy scans block the pipeline on any finding:
  - Image scan: known CVEs with available fixes
  - Config scan: Kubernetes security misconfigurations
  - Secret scan: accidentally committed credentials

### Infrastructure

- Cloud SQL connected via private IP (VPC peering) — not exposed on the public internet
- `terraform.tfvars` and state files excluded from version control
- Service account keys excluded from version control

---

## Infrastructure as Code

All GCP resources are managed by Terraform:

| Resource | Configuration |
|---|---|
| GKE Autopilot Cluster | `europe-west1`, REGULAR release channel, public nodes |
| Cloud SQL MySQL 8.4 | ENTERPRISE, `db-g1-small`, automated backups, IAM auth, `utf8mb4` |
| VPC | References existing GCP default network via data source |
| Terraform state | Remote backend on GCS (`webservice-devops-terraform-state`) |

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | >= 1.5.0 |
| gcloud CLI | Latest |
| kubectl | >= 1.26 |
| Helm | >= 3.0 |
| Vagrant | >= 2.3 (local deployment only) |
| VirtualBox | >= 6.1 (local deployment only) |

---

---

# WordPress sur Kubernetes — Deploiement Cloud et Local

Un projet de deploiement WordPress en conditions de production, couvrant deux modes de deploiement : un cluster Kubernetes local provisionne avec Vagrant et kubeadm, et un deploiement cloud-native sur Google Kubernetes Engine (GKE) avec un pipeline GitLab CI/CD entierement automatise.

---

## Table des matieres

- [Vue d'ensemble](#vue-densemble)
- [Architecture](#architecture-1)
- [Stack technique](#stack-technique)
- [Structure du projet](#structure-du-projet)
- [Modes de deploiement](#modes-de-deploiement)
- [Pipeline CI/CD](#pipeline-cicd)
- [Securite](#securite)
- [Infrastructure as Code](#infrastructure-as-code-1)
- [Prerequis](#prerequis)

---

## Vue d'ensemble

Ce projet illustre l'automatisation complete du deploiement d'une application WordPress dans deux environnements distincts :

- **Local** : Un cluster Kubernetes multi-noeuds cree avec Vagrant (VirtualBox) et initialise avec kubeadm, concu pour le developpement et les tests sans dependance au cloud.
- **Cloud** : Un deploiement en conditions de production sur GKE Autopilot avec une base de donnees Cloud SQL MySQL 8.4 geree, provisionnee entierement par Terraform et deployee via un pipeline GitLab CI/CD securise.

Le projet applique les principes DevOps de bout en bout : infrastructure as code, analyse de securite automatisee, promotion par environnements (review → staging → production), et zero credential statique grace a la federation OIDC.

---

## Architecture

### Architecture Cloud (GKE)

```
GitLab CI/CD (branche main)
        |
        | OIDC (Workload Identity Federation)
        v
   Projet GCP : webservice-devops
        |
        |-- Cluster GKE Autopilot (europe-west1)
        |       |-- Namespace : review-*     (ephemere par branche)
        |       |-- Namespace : staging
        |       |-- Namespace : wordpress    (production)
        |           |
        |           |-- Pod WordPress (bitnami/wordpress)
        |               |-- Service LoadBalancer
        |               |-- PersistentVolumeClaim (10Gi)
        |
        |-- Cloud SQL : MySQL 8.4 (ENTERPRISE, db-g1-small)
        |       |-- IP privee via VPC peering
        |       |-- Authentification IAM activee
        |       |-- Sauvegardes automatiques (quotidiennes a 02:00)
        |
        |-- Bucket GCS : etat Terraform distant
        |
        |-- VPC : reseau default GCP
```

### Architecture Locale (Vagrant + kubeadm)

```
Machine hote (VirtualBox)
        |
        |-- controlplane  (1 VM)
        |-- node01        (1 VM)
        |-- node02        (1 VM)
            |
            |-- Initialisation kubeadm
            |-- Deploiement WordPress (ClusterIP)
            |-- Deploiement MySQL + PersistentVolume
            |-- Nginx Ingress Controller
            |-- MetalLB (LoadBalancer bare-metal)
```

---

## Stack technique

| Categorie | Technologie |
|---|---|
| Orchestration de conteneurs | Kubernetes (GKE Autopilot, kubeadm) |
| Infrastructure as Code | Terraform >= 1.5 (Google provider ~> 5.0) |
| Gestionnaire de paquets K8s | Helm 3 (chart personnalise) |
| Base de donnees | Cloud SQL MySQL 8.4 / MySQL 5.6 (local) |
| CI/CD | GitLab CI/CD (7 stages) |
| Authentification | OIDC Workload Identity Federation (sans cle statique) |
| Analyse de securite | Trivy (images, config, secrets) |
| Image applicative | bitnami/wordpress (non-root, port 8080) |
| Provisionnement local | Vagrant + VirtualBox + kubeadm |
| Backend d'etat | Google Cloud Storage |
| Reseau | GCP VPC, VPC Peering (IP privee Cloud SQL) |
| Load Balancing | GKE LoadBalancer / MetalLB (local) |
| Ingress | Nginx Ingress Controller (local) / GKE natif (cloud) |
| Monitoring | Prometheus + Grafana (cluster local) |
| Sauvegarde | Velero (cluster local) |

---

## Structure du projet

```
wsdevops-Cloud/
|
|-- appli/                              # Couche applicative
|   |-- .gitlab-ci.yml                 # Pipeline CI/CD (7 stages)
|   |-- .gitlab/
|   |   |-- agents/                    # Configuration agents GitLab Kubernetes
|   |
|   |-- wordpress/                     # Chart Helm (personnalise)
|       |-- Chart.yaml
|       |-- values.yaml                # Valeurs par defaut (deploiement local)
|       |-- values-gke.yaml            # Valeurs de surcharge (deploiement GKE)
|       |-- templates/
|           |-- wordpress-deployment.yaml   # Avec securityContext strict
|           |-- wordpress-service.yaml
|           |-- ingress.yaml
|           |-- mysql-deployment.yaml       # Conditionnel (local uniquement)
|           |-- mysql-service.yaml          # Conditionnel (local uniquement)
|           |-- mysql-pvc.yaml              # Conditionnel (local uniquement)
|           |-- mysql-secrets.yaml          # Conditionnel (local uniquement)
|
|-- infra/                             # Couche infrastructure
    |-- terraform/                     # Provisionnement GCP
    |   |-- backend.tf                 # Etat distant GCS
    |   |-- main.tf                    # Cluster GKE + Cloud SQL + VPC
    |   |-- variables.tf
    |   |-- outputs.tf
    |
    |-- kubeadm_kubernetes/            # Provisionnement cluster local
        |-- Vagrantfile                # Definition des VMs multi-noeuds
        |-- settings.yaml              # Configuration du cluster
        |-- scripts/
        |   |-- common.sh              # Installation commune (tous les noeuds)
        |   |-- master.sh              # Initialisation du plan de controle
        |   |-- node.sh                # Jonction des noeuds worker
        |   |-- runner.sh              # Installation GitLab runner
        |   |-- LoadBalancer.sh        # Installation MetalLB
        |   |-- dashboard.sh           # Dashboard Kubernetes
        |-- cert-manager/              # Automatisation TLS
        |-- monitoring/                # Valeurs Prometheus + Grafana
        |-- velero/                    # Configuration des sauvegardes
```

---

## Modes de deploiement

### Deploiement local (Vagrant + kubeadm)

Prerequis : VirtualBox, Vagrant

```bash
cd infra/kubeadm_kubernetes
vagrant up
```

Cette commande provisionne un plan de controle et deux noeuds worker, initialise le cluster avec kubeadm, et installe automatiquement MetalLB, Nginx Ingress et cert-manager via les scripts de provisionnement.

Deployer WordPress en local :

```bash
helm upgrade --install wordpress appli/wordpress \
  -f appli/wordpress/values.yaml
```

### Deploiement Cloud (GKE + Terraform)

Prerequis : Terraform >= 1.5, gcloud CLI, kubectl, Helm 3

**Etape 1 — Provisionner l'infrastructure**

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars   # renseigner db_password
terraform init
terraform plan
terraform apply
```

Cette commande cree :
- Cluster GKE Autopilot dans `europe-west1`
- Instance Cloud SQL MySQL 8.4 avec connexion privee via VPC
- Liaisons IAM pour la federation Workload Identity

**Etape 2 — Configurer kubectl**

```bash
gcloud container clusters get-credentials wordpress-autopilot-cluster-1 \
  --region europe-west1 --project webservice-devops
```

**Etape 3 — Deployer via le pipeline**

Pousser sur `main`. Le pipeline GitLab CI/CD gere automatiquement le lint, les analyses de securite, le packaging et le deploiement.

**Detruire l'infrastructure**

```bash
terraform destroy
```

Toutes les ressources sont creees avec `deletion_protection = false` dans Terraform pour permettre une destruction propre.

---

## Pipeline CI/CD

Le pipeline est defini dans `appli/.gitlab-ci.yml` et se declenche a chaque push sur `main`.

```
Push branche main
      |
      v
  [test]              helm lint + helm template dry-run
      |
      v
  [security_test]     trivy image scan     (CVE CRITICAL avec correctif, bloquant)
                      trivy config scan    (mauvaises configs K8s HIGH/CRITICAL, bloquant)
                      trivy secret scan    (secrets dans le depot, bloquant)
      |
      v
  [release]           helm package -> artefact (.tgz)
      |
      v
  [deploy_review]     helm install -> namespace review-* (ephemere)
      |
      v
  [stop_review]       manuel — helm uninstall + suppression du namespace
      |
      v
  [deploy_staging]    helm upgrade --install -> namespace staging
      |
      v
  [deploy_prod]       validation manuelle — helm upgrade --install -> namespace wordpress
```

L'authentification GCP utilise la **federation OIDC Workload Identity** — aucune cle de compte de service n'est stockee dans GitLab. Le job CI echange un token GitLab de courte duree contre un token d'acces GCP au moment de l'execution.

**Variables CI/CD requises** (Settings > CI/CD > Variables) :

| Variable | Description |
|---|---|
| `GCP_PROJECT_ID` | ID du projet GCP |
| `GKE_CLUSTER_NAME` | Nom du cluster GKE |
| `GKE_REGION` | Region GCP |
| `WORDPRESS_DB_PASSWORD` | Mot de passe de la base (masque) |

**Parametre GitLab requis** : le chemin du fichier de configuration CI/CD doit etre defini a `appli/.gitlab-ci.yml`.

---

## Securite

### Securite des pods Kubernetes

Le deploiement WordPress applique des contraintes de securite strictes :

- Execution en utilisateur non-root (UID 1001, GID 1001) — conformite bitnami/wordpress
- `readOnlyRootFilesystem: true` — systeme de fichiers immuable a l'execution
- `allowPrivilegeEscalation: false`
- Toutes les capacites Linux supprimees (`drop: [ALL]`)
- `seccompProfile: RuntimeDefault`
- Acces en ecriture uniquement via des volumes `emptyDir` declares explicitement (tmp, logs, config apache, temp php)

### Securite CI/CD

- Aucun credential GCP statique — echange de token OIDC uniquement
- Mot de passe de la base injecte au moment du deploiement via `--set`, jamais stocke dans les fichiers values
- Trois analyses Trivy obligatoires bloquent le pipeline a la moindre detection :
  - Scan d'images : CVE connus avec correctif disponible
  - Scan de config : mauvaises configurations de securite Kubernetes
  - Scan de secrets : credentials commites par erreur

### Infrastructure

- Cloud SQL connecte via IP privee (VPC peering) — non expose sur Internet
- `terraform.tfvars` et fichiers d'etat exclus du controle de version
- Cles de compte de service exclues du controle de version

---

## Infrastructure as Code

Toutes les ressources GCP sont gerees par Terraform :

| Ressource | Configuration |
|---|---|
| Cluster GKE Autopilot | `europe-west1`, canal de mise a jour REGULAR, noeuds publics |
| Cloud SQL MySQL 8.4 | ENTERPRISE, `db-g1-small`, sauvegardes automatiques, auth IAM, `utf8mb4` |
| VPC | Reference le reseau GCP default existant via data source |
| Etat Terraform | Backend distant sur GCS (`webservice-devops-terraform-state`) |

---

## Prerequis

| Outil | Version |
|---|---|
| Terraform | >= 1.5.0 |
| gcloud CLI | Derniere version |
| kubectl | >= 1.26 |
| Helm | >= 3.0 |
| Vagrant | >= 2.3 (deploiement local uniquement) |
| VirtualBox | >= 6.1 (deploiement local uniquement) |
