# WordPress on Kubernetes — Hybrid GitOps Platform

Production-grade WordPress deployed on two Kubernetes environments — a local kubeadm cluster (Vagrant/VirtualBox) and a GKE Standard cluster on GCP — both managed **in GitOps** with ArgoCD. Infrastructure fully described in Terraform, secrets federated end-to-end (Workload Identity + External Secrets on GKE, Sealed Secrets locally), CI GitLab with three blocking Trivy scans and **no cluster access from the runner**.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Technology Stack](#technology-stack)
- [GitOps Model](#gitops-model)
- [Project Structure](#project-structure)
- [Deployment Modes](#deployment-modes)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security](#security)
- [Infrastructure as Code](#infrastructure-as-code)
- [Prerequisites](#prerequisites)


---

## Overview

An end-to-end DevOps project deploying the same application across two symmetric environments:

- **Local** — multi-node kubeadm cluster provisioned by Vagrant (control plane + workers), MySQL runs in-cluster, secrets sealed by [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), zero cloud dependencies.
- **Cloud** — GKE **Standard** zonal cluster with Spot VMs, managed **Cloud SQL MySQL 8.0** on private IP, secrets stored in **GCP Secret Manager** and federated to pods through **Workload Identity** + [External Secrets Operator](https://external-secrets.io/).

Both clusters run **the same Helm chart** with environment-specific values, both are driven by **ArgoCD in pull mode** — no `kubectl` and no `helm upgrade` is ever run manually after the initial bootstrap. A single GitLab CI pipeline validates and packages the chart; it has no credentials to any cluster.

**Guiding principles**: infrastructure as code, zero static credentials, security scanning by default, environment parity, GitOps as the single source of truth.

---

## Architecture

### GitOps flow (both environments)

```
                      git push (main)
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
   GitLab CI (validation)        GitLab repository = source of truth
   ├── helm lint / template            │
   ├── trivy image scan   (blocking)   │
   ├── trivy config scan  (blocking)   │
   ├── trivy secret scan  (blocking)   ▼ pull
   └── helm package (.tgz)   ┌─────────────────────────┐
                             │  ArgoCD (in-cluster)     │
                             │  reconciles every 3 min  │
                             │  self-heal + prune       │
                             └────────────┬─────────────┘
                                          │
                     ┌────────────────────┴────────────────────┐
                     ▼                                         ▼
         Local kubeadm cluster                        GKE Standard cluster
```

### Cloud environment (GKE)

```
GCP project: webservice-devops
│
├── GKE Standard cluster (europe-west1-b)          → Terraform-managed
│   ├── node pool: 2 × e2-small Spot VMs, 30 GB pd-standard
│   ├── Workload Identity enabled
│   ├── namespace argocd            → ArgoCD (5 pods)
│   ├── namespace external-secrets  → External Secrets Operator
│   ├── namespace staging           → WordPress (LoadBalancer)
│   └── namespace wordpress         → WordPress (LoadBalancer)
│
├── Cloud SQL MySQL 8.0 (db-f1-micro, HDD)         → Terraform-managed
│   └── Private IP only via VPC peering (no public exposure)
│
├── Secret Manager                                 → Terraform-managed
│   ├── wordpress-db-password
│   └── wordpress-admin-password
│
├── IAM: GSA eso-sa                                → Terraform-managed
│   ├── roles/secretmanager.secretAccessor
│   └── Workload Identity binding to KSA external-secrets/external-secrets
│
└── GCS bucket: Terraform remote state
```

### Local environment (Vagrant + kubeadm)

```
Host machine (VirtualBox)
│
├── master           (control plane)
├── noeud01          (worker)
├── noeud02          (worker, optional)
└── velero / runner  (optional, off by default)
    │
    └── Kubernetes 1.31 + Calico + MetalLB + Ingress-Nginx + cert-manager
        ├── namespace argocd    → ArgoCD (in-cluster)
        ├── namespace wordpress → WordPress + MySQL (in-cluster)
        └── namespace kube-system → Sealed Secrets controller
```

---

## Technology Stack

| Category | Technology |
|---|---|
| Container orchestration | Kubernetes (GKE Standard, kubeadm 1.31) |
| **GitOps** | **ArgoCD** — pull-mode, self-healing, prune |
| Infrastructure as code | Terraform ≥ 1.5 (Google provider ~> 5.0), state on GCS |
| Application packaging | Helm 3 — single custom chart, two value files |
| Secrets — cloud | **External Secrets Operator + GCP Secret Manager**, auth via **Workload Identity** |
| Secrets — local | **Sealed Secrets** (asymmetric encryption, committable to Git) |
| CI/CD | GitLab CI — **3 stages, 5 jobs** (validation only, no cluster access) |
| Security scanning | **Trivy** — image CVEs, K8s misconfigurations, committed secrets (all blocking) |
| CI ↔ GCP auth | OIDC Workload Identity Federation (no static keys) |
| Application image | `bitnami/wordpress` pinned by digest — non-root, `readOnlyRootFilesystem` |
| Database — cloud | Cloud SQL MySQL 8.0 (db-f1-micro, HDD, private IP) |
| Database — local | MySQL in-cluster (Deployment + PVC) |
| Local provisioning | Vagrant + VirtualBox + shell scripts |
| Networking | GCP VPC (peering to Cloud SQL) / Calico + MetalLB (local) |
| Load balancing | GKE LoadBalancer (cloud) / MetalLB (local) |
| Ingress | GKE Service (cloud) / Ingress-Nginx (local) |

---

## GitOps Model

The pipeline validates. ArgoCD deploys. The two are decoupled:

```
CI runner                                Cluster
────────────                             ────────
- no kubeconfig                          - ArgoCD polls Git every 3 min
- no cluster credentials                 - reconciles state to match main
- no gcloud on validation jobs           - self-heal reverts manual drift
- just Helm + Trivy                      - prune removes what Git removes
```

**Concrete guarantees**:
- Any `kubectl edit`/`scale` on the cluster is detected and reverted within ~3 minutes (`selfHeal: true`)
- Rolling back a bad change is `git revert` + push (~2-3 min end-to-end)
- Resurrecting a lost cluster: `terraform apply` → install ArgoCD → apply Applications → **the whole platform redeploys itself** from Git
- The runner has no admin rights — dramatically reduced attack surface
- The same chart is validated in both **local** and **GKE** modes at every push

**Measured resilience tests** (from the `main` branch history):

| Simulated incident | Recovery |
|---|---|
| `kubectl scale --replicas=5` (rogue drift) | Auto-reverted in **~3 min** |
| `kubectl delete deployment` (deletion) | Recreated in **~20 s** |
| Change deployed via `git push` | Live in **~90 s** |
| Rollback via `git revert` | Effective in **~2-3 min** |

---

## Project Structure

```
wsdevops-Cloud/
│
├── appli/                              # Application layer
│   ├── .gitlab-ci.yml                  # CI: validation only (test + 3 Trivy + release)
│   │
│   ├── wordpress/                      # Custom Helm chart
│   │   ├── Chart.yaml
│   │   ├── values.yaml                 # Defaults (local: MySQL in-cluster, Ingress-Nginx)
│   │   ├── values-gke.yaml             # Overrides (GKE: Cloud SQL, LoadBalancer, ESO)
│   │   └── templates/
│   │       ├── wordpress-deployment.yaml   # non-root, RO rootfs, initContainer prepare-base-dir
│   │       ├── wordpress-service.yaml
│   │       ├── wordpress-pvc.yaml
│   │       ├── mysql-client-config.yaml    # (GKE) my.cnf mounted to fix TLS-verify quirk
│   │       ├── mysql-*.yaml                # (local only) Deployment/Service/PVC/Secret
│   │       └── ingress.yaml
│   │
│   └── gitops/                         # ArgoCD Applications (declarative deploy config)
│       ├── local/
│       │   ├── wordpress-local.yaml    # auto-sync + selfHeal + prune
│       │   ├── secrets-app.yaml
│       │   └── secrets/mysql-sealed-secret.yaml  # committable, encrypted
│       └── gke/
│           ├── wordpress-staging.yaml  # auto-sync
│           ├── wordpress-prod.yaml     # manual sync (human gate for prod)
│           ├── secrets-app.yaml
│           └── secrets/
│               ├── cluster-secret-store.yaml     # GCP Secret Manager backend
│               └── external-secret-*.yaml        # references (values fetched by ESO)
│
└── infra/                              # Infrastructure layer
    ├── terraform/                      # 10 resources under Terraform (imported from console)
    │   ├── main.tf                     # cluster + node pool + Cloud SQL + IAM + Secret Manager
    │   ├── variables.tf
    │   ├── outputs.tf
    │   └── backend.tf                  # state on GCS bucket webservice-devops-terraform-state
    │
    └── kubeadm_kubernetes/             # Local cluster provisioning
        ├── Vagrantfile
        ├── settings.yaml
        ├── scripts/                    # common, master, node, LoadBalancer (MetalLB)
        ├── cert-manager/               # TLS automation (local)
        ├── monitoring/                 # Prometheus + Grafana (planned)
        └── velero/                     # Backup (planned)
```

---

## Deployment Modes

### Local (Vagrant + kubeadm + Sealed Secrets)

Prerequisites: VirtualBox, Vagrant, ≥ 8 GB free RAM on the host.

```bash
# 1. Provision the cluster (master + one worker is enough)
cd infra/kubeadm_kubernetes
vagrant up master noeud01

# 2. Install the platform (one-time bootstrap, from a shell with kubectl configured)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set dex.enabled=false --set notifications.enabled=false

helm repo add sealed-secrets https://bitnami.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system \
  --set fullnameOverride=sealed-secrets-controller

# 3. Point ArgoCD at Git (once) and register the two Applications
kubectl apply -f appli/gitops/local/wordpress-local.yaml \
              -f appli/gitops/local/secrets-app.yaml

# From then on: every git push is deployed automatically.
```

### Cloud (GKE Standard + Cloud SQL + ESO)

Prerequisites: Terraform ≥ 1.5, `gcloud`, `kubectl`, `helm`.

```bash
# 1. Provision GCP resources (or import existing ones — code is aligned with reality)
cd infra/terraform
terraform init
terraform apply             # cluster, node pool, Cloud SQL, IAM, Secret Manager

# 2. Populate secrets in Secret Manager (values never touch Git)
gcloud secrets versions add wordpress-db-password    --data-file=/path/to/db.txt
gcloud secrets versions add wordpress-admin-password --data-file=/path/to/wp.txt

# 3. Bootstrap the platform (one-time)
gcloud container clusters get-credentials cluster-1 --zone europe-west1-b
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set dex.enabled=false --set notifications.enabled=false
helm install external-secrets external-secrets/external-secrets -n external-secrets \
  --create-namespace \
  --set "serviceAccount.annotations.iam\.gke\.io/gcp-service-account=eso-sa@<PROJECT>.iam.gserviceaccount.com"

kubectl apply -f appli/gitops/gke/wordpress-staging.yaml \
              -f appli/gitops/gke/wordpress-prod.yaml \
              -f appli/gitops/gke/secrets-app.yaml
```

---

## CI/CD Pipeline

Defined in `appli/.gitlab-ci.yml`. **Validation only** — no cluster access.

```
git push main
      │
      ▼
[test]              helm lint + helm template (local and GKE modes)
      │
      ▼
[security_test]     trivy image scan     (CRITICAL CVEs with fix — blocking)
                    trivy config scan    (HIGH/CRITICAL K8s misconfigs — blocking)
                    trivy secret scan    (committed secrets — blocking)
      │
      ▼
[release]           helm package → .tgz artifact
```

**Deployments are performed by ArgoCD, not by the pipeline.** The historical `deploy_review / staging / prod` jobs were removed after the GitOps migration (−145 lines of CI).

Duration: ~3-5 minutes per push. Zero credentials to any cluster.

**Required setting** in GitLab: **Settings → CI/CD → General pipelines → CI/CD configuration file** = `appli/.gitlab-ci.yml`.

---

## Security

### Pod-level

- Non-root (UID 1001), `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false`
- All Linux capabilities dropped, `seccompProfile: RuntimeDefault`
- Writes only through explicit `emptyDir` subPaths (Apache logs, PHP tmp, app base dir populated by initContainer)
- `bitnami/wordpress` pinned by SHA digest (reproducible builds, no floating `latest`)

### Secrets

- **Nothing sensitive in Git** — ever. The repository stores only references (`ExternalSecret`) or ciphertext (`SealedSecret`).
- **Zero static credentials end-to-end**:
  - CI → GCP: OIDC Workload Identity Federation
  - Pod → GCP APIs: Workload Identity binding (KSA ↔ GSA)
  - `terraform.tfvars` is gitignored (holds the DB password locally only)

### CI

- Three blocking Trivy scans on every push — no way to merge a critical CVE, a K8s misconfiguration, or a leaked secret
- The runner has no cluster or GCP credentials for the validation jobs

### Infrastructure

- Cloud SQL exposed on **private IP only** (no public interface, VPC peering)
- GKE control plane in the REGULAR release channel
- Shielded nodes: integrity monitoring + secure boot
- Deletion protection managed by Terraform (off in this lab; would be on in real production)

---

## Infrastructure as Code

All GCP resources are described in Terraform — including the pieces originally created via the console, which have been **imported** into the state:

| Resource | Notes |
|---|---|
| GKE Standard cluster + node pool | zonal, Workload Identity, Spot VMs, `ignore_changes` on Google-managed cosmetic blocks |
| Cloud SQL MySQL 8.0 instance + database + user | private IP, no backups (lab), `activation_policy` parameterised |
| Secret Manager (2 secret containers, values managed out-of-band) | |
| GSA `eso-sa` + project IAM binding + Workload Identity binding | Least-privilege: only `roles/secretmanager.secretAccessor` |

`terraform plan` runs clean: **no destroy, no add**. Code is the map of production.

The state lives in GCS bucket `webservice-devops-terraform-state`, encrypted at rest. Locking prevents concurrent applies.

---

## Prerequisites

| Tool | Version |
|---|---|
| Terraform | ≥ 1.5.0 |
| gcloud CLI | latest |
| kubectl | ≥ 1.28 |
| Helm | ≥ 3.16 |
| Vagrant | ≥ 2.3 (local only) |
| VirtualBox | ≥ 6.1 (local only) |
