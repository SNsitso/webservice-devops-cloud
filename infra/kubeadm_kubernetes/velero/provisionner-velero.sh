#!/bin/bash
set -e

# Variables MinIO
MINIO_USER=velero
MINIO_PASSWORD=velero123
MINIO_DATA=/data/minio

echo "=== Mise à jour système ==="
apt-get update -y

echo "=== Installation Docker ==="
apt-get install -y docker.io curl
systemctl enable docker
systemctl start docker

echo "=== Création dossier MinIO ==="
mkdir -p $MINIO_DATA
chmod -R 755 /data

echo "=== Lancement MinIO ==="
docker run -d \
  --name minio \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -v $MINIO_DATA:/data \
  -e MINIO_ROOT_USER=$MINIO_USER \
  -e MINIO_ROOT_PASSWORD=$MINIO_PASSWORD \
  quay.io/minio/minio server /data --console-address ":9001"

echo "=== MinIO prêt ==="
