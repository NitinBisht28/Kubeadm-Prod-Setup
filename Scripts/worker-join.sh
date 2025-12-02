#!/bin/bash
set -e

echo "Checking if join command file exists..."

if [ ! -f join-command.sh ]; then
  echo "join-command.sh not found."
  echo "Please copy the file from the master node using scp:"
  echo "scp -i <pem> ubuntu@<MASTER_PUBLIC_IP>:/home/ubuntu/join-command.sh ."
  exit 1
fi

chmod +x join-command.sh
sudo ./join-command.sh --v=5

echo "Worker join command executed."
echo "Waiting for node registration..."
sleep 20

echo "Checking node status..."
kubectl get nodes -o wide || true

echo "Worker setup completed."

