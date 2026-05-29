#!/bin/bash
#
# Setup for runner

# Mise à jour du système
apt-get update -y
apt-get upgrade -y

# Installation des dépendances
apt-get install -y \
ca-certificates \
curl \
gnupg \
lsb-release \
apt-transport-https

set -euxo pipefail

# DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	sudo mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

sudo systemctl restart systemd-resolved

# disable swap
sudo swapoff -a

# keeps the swaf off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y


# Installation de Docker 
curl -fsSL https://get.docker.com | sh
usermod -aG docker vagrant

#Installation de GitLab Runner
curl -L https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh | bash
apt-get install -y gitlab-runner

# Configuration Docker pour GitLab Runner 
usermod -aG docker gitlab-runner

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Activation des services
systemctl enable docker
systemctl enable gitlab-runner
systemctl start docker
systemctl start gitlab-runner