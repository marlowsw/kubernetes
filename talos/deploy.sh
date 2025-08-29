#!/bin/bash

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Proxmox host ssh target
PROXMOX_HOST="root@nas1"
PROXMOX_HOST1="root@mini1"
PROXMOX_HOST2="root@mini2"
PROXMOX_HOST3="root@mini3"

# Configurations
ISO_STORAGE="NVME-NFS-Image"
ISO_FILE="iso/talos.iso"
DISK_STORAGE="NVME-NFS-Image"
CPU=4
MEMORY=8192
DISK_SIZE="20G"

# === Create VM function ===
create_vm() {
  local proxmox_host=$1
  local vmid=$2
  local name=$3
  local macaddr=$4

  echo -e "${YELLOW}Creating VM $name ($vmid) on $proxmox_host...${NC}"

  ssh $proxmox_host bash -s <<EOF
set -e
mkdir -p /mnt/pve/$DISK_STORAGE/images/$vmid

qemu-img create -f qcow2 /mnt/pve/$DISK_STORAGE/images/$vmid/vm-$vmid-disk-0.qcow2 $DISK_SIZE

qm create $vmid --cdrom $ISO_STORAGE:$ISO_FILE \
  --name $name \
  --numa 0 \
  --ostype l26 \
  --cpu cputype=host \
  --cores $CPU --sockets 1 \
  --memory $MEMORY \
  --net0 model=virtio,bridge=vmbr0,macaddr=$macaddr \
  --bootdisk scsi0 \
  --scsihw virtio-scsi-pci \
  --scsi0 file=$DISK_STORAGE:20 \
  --serial0 socket

qm start $vmid
EOF
}

# === Node creation ===
echo -e "${YELLOW}Creating control-plane nodes...${NC}"
create_vm $PROXMOX_HOST 107 "talos-control-1" bc:24:11:a4:03:10
sleep 30
create_vm $PROXMOX_HOST1 201 "talos-control-2" bc:24:11:27:7b:98
sleep 30
create_vm $PROXMOX_HOST2 301 "talos-control-3" bc:24:11:2d:eb:88
sleep 30

echo -e "${YELLOW}Creating worker nodes...${NC}"
create_vm $PROXMOX_HOST 108 "talos-worker-1" bc:24:11:5f:81:3c
sleep 30
create_vm $PROXMOX_HOST 109 "talos-worker-2" bc:24:11:80:db:1c
sleep 30
create_vm $PROXMOX_HOST1 202 "talos-worker-3" bc:24:11:9f:5a:6a
sleep 30
create_vm $PROXMOX_HOST1 203 "talos-worker-4" bc:24:11:f6:7f:6c
sleep 30
create_vm $PROXMOX_HOST2 302 "talos-worker-5" bc:24:11:f3:d7:cb
sleep 30
create_vm $PROXMOX_HOST2 303 "talos-worker-6" bc:24:11:a5:4a:fa
sleep 30
create_vm $PROXMOX_HOST3 401 "talos-worker-7" bc:24:11:54:e5:eb
sleep 30
create_vm $PROXMOX_HOST3 402 "talos-worker-8" bc:24:11:12:76:59
sleep 30
create_vm $PROXMOX_HOST3 403 "talos-worker-9" bc:24:11:0b:87:32

sleep 30

echo -e "${GREEN}All nodes are up! Generating Talos Kubernetes cluster config files...${NC}"
talosctl gen config talos-proxmox-cluster https://10.0.0.155:6443 --output-dir /home/smarz/talos

sleep 30

# === Apply config to control planes ===
echo -e "${YELLOW}Applying control plane configurations...${NC}"
talosctl apply-config -e 10.0.0.155 -n 10.0.0.155 --insecure -f /home/smarz/talos/controlplane.yaml
sleep 30
talosctl apply-config -e 10.0.0.131 -n 10.0.0.131 --insecure -f /home/smarz/talos/controlplane.yaml
sleep 30
talosctl apply-config -e 10.0.0.132 -n 10.0.0.132 --insecure -f /home/smarz/talos/controlplane.yaml
sleep 20

# === Apply config to workers ===
echo -e "${YELLOW}Applying worker configurations...${NC}"
talosctl apply-config -e 10.0.0.133 -n 10.0.0.133 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.134 -n 10.0.0.134 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.139 -n 10.0.0.139 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.135 -n 10.0.0.135 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.136 -n 10.0.0.136 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.137 -n 10.0.0.137 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.138 -n 10.0.0.138 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.156 -n 10.0.0.156 --insecure -f /home/smarz/talos/worker.yaml
sleep 20
talosctl apply-config -e 10.0.0.130 -n 10.0.0.130 --insecure -f /home/smarz/talos/worker.yaml

sleep 300

echo -e "${GREEN}All nodes are up! Generating Talos Kubernetes cluster config files...${NC}"
talosctl gen config talos-proxmox-cluster https://10.0.0.155:6443 --output-dir /home/smarz/talos
sleep 30

# === Apply configs automatically ===
#for vm in "${VM_PLAN[@]}"; do
#  read proxmox_host vmid name mac ip role <<<"$vm"
#
#  if [[ "$role" == "controlplane" ]]; then
#    echo -e "${YELLOW}Applying control plane config to $name ($ip)...${NC}"
#    talosctl apply-config -e $ip -n $ip --insecure -f /home/smarz/talos/controlplane.yaml
#  else
#    echo -e "${YELLOW}Applying worker config to $name ($ip)...${NC}"
#    talosctl apply-config -e $ip -n $ip --insecure -f /home/smarz/talos/worker.yaml
#  fi
#
#  sleep 20
#done

# === Set Talos client & generate kubeconfig ===
echo -e "${GREEN}Setting TALOSCONFIG path...${NC}"
export TALOSCONFIG="/home/smarz/talos/talosconfig"

sleep 20

echo -e "${YELLOW}Configuring Talos client endpoint...${NC}"
talosctl config endpoint 10.0.0.155

echo -e "${YELLOW}Configuring Talos client nodes...${NC}"
talosctl config nodes 10.0.0.155
sleep 30

echo -e "${GREEN}Generating kubeconfig from Talos cluster...${NC}"
talosctl kubeconfig . -f
sleep 30

echo -e "${GREEN}Exporting KUBECONFIG...${NC}"
export KUBECONFIG=kubeconfig
sleep 10

echo -e "${RED}Bootstrapping Talos Kubernetes cluster...${NC}"
talosctl bootstrap
sleep 300

echo -e "${GREEN}Checking for nodes...${NC}"
kubectl get nodes

sleep 30

echo -e "${GREEN}Waiting for API server to stabilize...${NC}"
until kubectl get nodes >/dev/null 2>&1; do
  echo "API not ready yet, retrying in 10s..."
  sleep 10
done

echo -e "${GREEN}Installing Kubernetes-csi-nfs-driver...${NC}"
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts

helm repo update

sleep 10

helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs \
    --namespace kube-system \
    --set kubeletDir=/var/lib/kubelet

sleep 120


kubectl get pods -n kube-system

sleep 30

echo -e "${GREEN}Creating StorageClass...${NC}"
cat <<EOF > sc-nfs.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: 10.0.0.90
  share: /mnt/Labdata
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
EOF

sleep 10

kubectl apply -f sc-nfs.yaml

echo -e "${GREEN}Creating Test PVC...${NC}"
cat <<EOF > pvc-nfs.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  storageClassName: nfs-csi
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
EOF

kubectl apply -f pvc-nfs.yaml

sleep 10

kubectl get pvc

echo -e "${GREEN}Installing Kubernetes Metrics Server...${NC}"

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

sleep 30

kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

sleep 30

kubectl get pods -n kube-system |grep -i metric

sleep 10

echo -e "${GREEN}Applying label to worker nodes...${NC}"
kubectl label node talos-1 node-role.kubernetes.io/worker=worker
kubectl label node talos-2 node-role.kubernetes.io/worker=worker
kubectl label node talos-3 node-role.kubernetes.io/worker=worker
kubectl label node talos-worker-1 node-role.kubernetes.io/worker=worker
kubectl label node talos-worker-2 node-role.kubernetes.io/worker=worker
kubectl label node talos-worker-3 node-role.kubernetes.io/worker=worker
kubectl label node talos-test-1 node-role.kubernetes.io/worker=worker
kubectl label node talos-test-2 node-role.kubernetes.io/worker=worker
kubectl label node talos-test-3 node-role.kubernetes.io/worker=worker


sleep 10

echo -e "${GREEN}Installing Cert-Manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml

# Wait for the webhook to become available
echo -e "${GREEN}Waiting for cert-manager-webhook to become available...${NC}"
kubectl wait --namespace cert-manager \
  --for=condition=Available deployment/cert-manager-webhook \
  --timeout=120s

echo -e "${GREEN}Applying letsencrypt ClusterIssuer...${NC}"
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
  namespace: cert-manager
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: support@drunkcoding.net
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
EOF

sleep 10

echo -e "${GREEN}Installing the Kubernetes Dashboard...${NC}"
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/

helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard

sleep 30

echo -e "${GREEN}Creating Admin User...${NC}"

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

echo -e "${GREEN}Exposing the Kubernetes Dashboard...${NC}"
nohup kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 --address 0.0.0.0 > /tmp/kdash.log 2>&1 &

echo -e "${GREEN}Generating login token...${NC}"
kubectl -n kubernetes-dashboard create token admin-user --duration=8000h

echo -e "${GREEN}Use the token above to login to your cluster at https://<your-node-ip>:8443...${NC}"

