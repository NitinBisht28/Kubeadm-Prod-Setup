#!/bin/bash
set -e

MASTER_HOSTNAME="master-cp"
POD_CIDR="192.168.0.0/16"

echo "Setting hostname to $MASTER_HOSTNAME..."
sudo hostnamectl set-hostname $MASTER_HOSTNAME
echo "127.0.0.1 $MASTER_HOSTNAME" | sudo tee -a /etc/hosts

echo "Detecting ENI private IP..."
ENI_IP=$(hostname -I | awk '{print $1}')
echo "Using ENI IP: $ENI_IP"

echo "Initializing Kubernetes control plane..."
sudo kubeadm init \
  --apiserver-advertise-address=$ENI_IP \
  --pod-network-cidr=$POD_CIDR

echo "Configuring kubectl for the current user..."
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Installing Calico CNI..."
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml

echo "Saving worker join command..."
kubeadm token create --print-join-command > join-command.sh
chmod +x join-command.sh

echo "Waiting for nodes to initialize..."
sleep 20
kubectl get nodes -o wide

echo "Master setup completed successfully."
echo "Run 'join-command.sh' on the worker node to join the cluster."
cat join-command.sh
