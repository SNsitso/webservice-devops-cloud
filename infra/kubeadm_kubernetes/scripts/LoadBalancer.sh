#!/bin/bash
set -euo pipefail

echo "=== SCRIPT FINAL : Déploiement LoadBalancer (MetalLB) ==="

# Attendre que les workers soient prêts
kubectl wait --for=condition=Ready node --all --timeout=600s

# Vérification des nœuds du cluster
kubectl get nodes -o wide

echo "=== Installation Ingress ==="    

# Installer Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

echo "=== Installation cert-manager ==="    
# Installer cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

echo "=== Installation LoadBAlancer ==="    
# Install LoadBalancer

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
    
kubectl wait --namespace metallb-system \
    --for=condition=Ready pod \
    --all \
    --timeout=300s

kubectl apply -f /vagrant/scripts/MetalLb/metallb-config.yaml

# Install Metrics Server

kubectl apply -f https://raw.githubusercontent.com/techiescamp/kubeadm-scripts/main/manifests/metrics-server.yaml


echo "=== Installation Garafana et prometheus ==="    
# ====================Install Prometheus + Grafana + Alertmanager ==================

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

#kubectl create namespace monitoring 

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace  -f /vagrant/monitoring/values-monitoring.yaml || true

echo "=== Installation velero ==="    
# ===============Install Velero========================================

#kubectl create namespace velero

#kubectl create secret generic cloud-credentials \
#  --namespace velero \
#  --from-file=cloud=/vagrant/velero/credentials-velero

# ajouter le repo helm velero
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

#installer le cli velero

VELERO_VERSION=v1.13.2

curl -LO https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-amd64.tar.gz
tar -xvf velero-${VELERO_VERSION}-linux-amd64.tar.gz
sudo mv velero-${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/


#velero install --crds-only --dry-run -o yaml | kubectl apply -f -

helm upgrade --install velero vmware-tanzu/velero \
  --namespace velero \
  --create-namespace \
  -f /vagrant/velero/values-velero.yaml 


