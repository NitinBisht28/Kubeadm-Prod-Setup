# 🚀 Kubernetes Production Cluster Setup
### Installation, Backup & Disaster Recovery with kubeadm

A complete, production‑grade guide for deploying Kubernetes on AWS using **kubeadm**, including **Backup + Disaster Recovery (DR)** best practices.

---

## 1️⃣ Introduction
This guide helps you:
- 🎯 Deploy a Kubernetes cluster using kubeadm on AWS
- 🔐 Back up critical Kubernetes components
- 🔄 Restore and recover the cluster during a failure

### 🧰 Prerequisites
- 🐧 Ubuntu 20.04 or later
- 🧑‍💻 `sudo` privileges
- 🌐 Internet access
- 💻 EC2 instance type: t2.medium or higher

### ☁️ AWS Setup Overview
- 🛡 All nodes in **same Security Group**
- 🧩 Create + attach a **custom ENI** with static private IP
- 🔓 Open inbound ports:
  - 22 (SSH) 🔑
  - 6443 (Kubernetes API) 🔁

---

## 2️⃣ Kubernetes Installation & Cluster Setup

### 🌐 AWS Networking Preparation
Before creating the Master node:
1. 🧩 Create ENI
2. 🔐 Assign static private IP
3. 🔗 Attach ENI to Master
4. ▶ Use ENI private IP for `kubeadm init`

> 🔹 Prevents IP/cert conflicts during DR

---

### 🔄 Common Setup (Master & Worker Nodes)
Run on **all nodes** 👇

#### 🔕 Disable Swap
```bash
sudo swapoff -a
```

#### 🔧 Load Kernel Modules
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
```

#### 🌐 Apply Sysctl Params
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

#### 📦 Install containerd
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y containerd.io

containerd config default | sed -e 's/SystemdCgroup = false/SystemdCgroup = true/' | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable --now containerd
```

#### 🚀 Install Kubernetes Components (v1.29)
```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl

sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl etcd-client
sudo apt-mark hold kubelet kubeadm kubectl
```
> 🔹 All nodes must run SAME Kubernetes versions!

---

### 🖥 Master Node Setup
#### 🏷 Set Hostname
```bash
sudo hostnamectl set-hostname master-cp
echo "127.0.0.1 master-cp" | sudo tee -a /etc/hosts
```
> ⚠️ Required for Disaster Recovery

#### 🚀 Initialize the Control Plane
```bash
sudo kubeadm init --apiserver-advertise-address=<ENI-PRIVATE-IP> --pod-network-cidr=192.168.0.0/16
```

#### 🔑 Configure kubeconfig
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

#### 🌐 Install CNI (Calico)
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.0/manifests/calico.yaml
```

#### 🔗 Get Worker Join Command
```bash
kubeadm token create --print-join-command
```

---

### 👷 Worker Node Setup
Add:
- `sudo` at beginning
- `--v=5` at end

Example:
```bash
sudo kubeadm join <ENI-IP>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash> --cri-socket "unix:///run/containerd/containerd.sock" --v=5
```

---

### 🔍 Verify Nodes
```bash
kubectl get nodes -o wide
```
✔ All should be **Ready**

---

## 3️⃣ Backup Strategy (Master Only)
### 📦 What to Backup
| Component | Path | Purpose |
|----------|------|---------|
| 💾 ETCD Snapshot | `/var/lib/etcd` | Cluster state |
| 🔐 Kubernetes Configs | `/etc/kubernetes/` | API certs & configs |
| 🆔 Kubelet Identity | `/var/lib/kubelet` | Node certificates |

#### ⏺ Take ETCD Snapshot
```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /root/k8s-backup/etcd.db \
 --endpoints=https://127.0.0.1:2379 \
 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
 --cert=/etc/kubernetes/pki/etcd/server.crt \
 --key=/etc/kubernetes/pki/etcd/server.key
```

#### 🗂 Backup configs
```bash
sudo mkdir -p /root/k8s-backup
sudo cp -r /etc/kubernetes /root/k8s-backup/kubernetes
sudo cp -r /var/lib/kubelet /root/k8s-backup/kubelet
sudo -i
cd /root
sudo tar czf k8s-backup.tar.gz k8s-backup
```

#### ☁ Upload to S3
> 🔹 If this EC2 instance has an **IAM Role** with S3 permissions — **NO** `aws configure` is required
> 🔹 If restoring from a laptop or non‑role instance — run `aws configure` first

**AWS Credential Requirements**
| Environment | Need `aws configure`? | Why |
|------------|:--------------------:|-----|
| EC2 with IAM Role | ❌ No | Auto temporary credentials ✔ |
| EC2 w/out IAM Role | ✅ Yes | No automatic credentials |
| Laptop / external machine | ✅ Yes | Needs manual keys |

```bash
aws s3 cp /root/k8s-backup.tar.gz s3://<bucket>/k8s-backups/$(date +%F-%H%M).tar.gz
```
```bash
aws s3 cp /root/k8s-backup.tar.gz s3://<bucket>/k8s-backups/$(date +%F-%H%M).tar.gz
```
> 🔹 Requires AWS CLI & IAM role with S3 permissions

---

## 4️⃣ Disaster Recovery — Master Failure
Launch replacement Master with:
- Same ENI ⚙️
- Same hostname 🏷

#### 📥 Download Backup
```bash
aws s3 cp s3://<bucket>/k8s-backups/<file>.tar.gz /root/k8s-backup.tar.gz
```

#### 🔄 Restore Data
```bash
sudo systemctl stop kubelet
sudo rm -rf /var/lib/etcd
sudo ETCDCTL_API=3 etcdctl snapshot restore /root/k8s-backup/etcd.db --data-dir=/var/lib/etcd
sudo tar xzf /root/k8s-backup.tar.gz -C /
sudo systemctl restart kubelet
```

#### 🔍 Validate Recovery
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get svc -A
```
✔ Cluster restored automatically in 30–60 sec

---

## 5️⃣ Final Production Checklist
| Category | Required |
|---------|:-------:|
| Swap disabled | ✔️ |
| Static ENI private IP | ✔️ |
| Same hostname (`master-cp`) | ✔️ |
| Same Kubernetes versions | ✔️ |
| Backup stored safely | ✔️ |
| No `kubeadm init` during DR | ✔️ |
| Nodes Ready after restore | ✔️ |

---

## 🎯 Conclusion
You now have:
- 🔐 Highly available cluster design
- 💾 Reliable backup workflow
- 🔄 Fully tested DR procedure

✨ You're production‑ready!

