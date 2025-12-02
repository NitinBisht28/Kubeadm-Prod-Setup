#!/bin/bash
set -e

S3_BUCKET="<your-s3-bucket-name>"
BACKUP_FILE="<backup-file-name>.tar.gz"
MASTER_HOSTNAME="master-cp"

echo "Setting hostname for restored master..."
sudo hostnamectl set-hostname $MASTER_HOSTNAME
echo "127.0.0.1 $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

echo "Installing needed dependencies for restore..."
sudo apt-get update
sudo apt-get install -y etcd-client

echo "Downloading backup from S3..."
aws s3 cp s3://$S3_BUCKET/k8s-backups/$BACKUP_FILE /root/$BACKUP_FILE

echo "Extracting backup..."
cd /
sudo tar xzf /root/$BACKUP_FILE

echo "Restoring etcd data..."
sudo systemctl stop kubelet
sudo rm -rf /var/lib/etcd
sudo mkdir -p /var/lib/etcd

sudo ETCDCTL_API=3 etcdctl snapshot restore /root/k8s-backup/etcd.db \
  --data-dir=/var/lib/etcd

sudo chown -R root:root /var/lib/etcd /etc/kubernetes /var/lib/kubelet

echo "Restarting kubelet..."
sudo systemctl start kubelet

echo "Waiting for cluster to recover..."
sleep 30

echo "Cluster state:"
kubectl get nodes -o wide || true
kubectl get pods -A || true

echo "Restore process completed."
