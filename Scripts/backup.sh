#!/bin/bash
set -e

BACKUP_DIR="/root/k8s-backup"
BACKUP_FILE="k8s-backup-$(date +%F-%H%M).tar.gz"
S3_BUCKET="<your-s3-bucket-name>"

echo "Creating backup directory..."
sudo rm -rf $BACKUP_DIR
sudo mkdir -p $BACKUP_DIR

echo "Taking etcd snapshot..."
sudo ETCDCTL_API=3 etcdctl snapshot save $BACKUP_DIR/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

echo "Backing up Kubernetes configs..."
sudo cp -r /etc/kubernetes $BACKUP_DIR/kubernetes
sudo cp -r /var/lib/kubelet $BACKUP_DIR/kubelet

echo "Compressing backup..."
cd /root
sudo tar -czf $BACKUP_FILE k8s-backup

echo "Uploading to S3..."
aws s3 cp $BACKUP_FILE s3://$S3_BUCKET/k8s-backups/$BACKUP_FILE

echo "Backup upload completed successfully."
aws s3 ls s3://$S3_BUCKET/k8s-backups/

echo "Backup complete."

