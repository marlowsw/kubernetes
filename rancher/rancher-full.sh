#!/bin/bash

set -euo pipefail

############################################
# CONFIG
############################################

SSH_USER="smarz"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Proxmox Hosts
PROXMOX_HOST1="root@nas1"
#PROXMOX_HOST2="root@mini1"
#PROXMOX_HOST3="root@mini2"
#PROXMOX_HOST4="root@mini3"

declare -A NODE_HOST_MAP=(
  [rancher-control1]=$PROXMOX_HOST1
  [rancher-control2]=$PROXMOX_HOST1
  [rancher-control3]=$PROXMOX_HOST1
  [rancher-worker1]=$PROXMOX_HOST1
  [rancher-worker2]=$PROXMOX_HOST1
  [rancher-worker3]=$PROXMOX_HOST1
)

declare -A TEMPLATE_MAP=(
#  [$PROXMOX_HOST2]=996
#  [$PROXMOX_HOST3]=996
#  [$PROXMOX_HOST4]=996
  [$PROXMOX_HOST1]=777
)

declare -A NODE_IPS=(
  [rancher-control1]=10.0.0.249
  [rancher-control2]=10.0.0.244
  [rancher-control3]=10.0.0.235
  [rancher-worker1]=10.0.0.204
  [rancher-worker2]=10.0.0.222
  [rancher-worker3]=10.0.0.205
)

CONTROL_NODES=(
  rancher-control1
  rancher-control2
  rancher-control3
)

WORKER_NODES=(
  rancher-worker1
  rancher-worker2
  rancher-worker3
)

CPU=4
MEMORY_CONTROL=8192
MEMORY_WORKER=16384
BRIDGE="vmbr0"

NVME_STORAGE="NVME-NFS"
# NFS_STORAGE="NAS"

RKE2_TOKEN="admin"

# Rancher
RANCHER_HOSTNAME="rancher-control1"
RANCHER_BOOTSTRAP_PASSWORD="admin"

# NFS
NFS_SERVER="10.0.0.9"
NFS_SHARE="/Volume2/proxmox/k8s"

############################################
# HELPERS
############################################

log() {
  echo -e "\n${GREEN}==== $1 ====${NC}\n"
}

warn() {
  echo -e "${YELLOW}WARNING: $1${NC}"
}

error() {
  echo -e "${RED}ERROR: $1${NC}"
}

run_ssh() {
  local ip="$1"
  shift

  ssh $SSH_OPTS \
    "${SSH_USER}@${ip}" \
    "bash -lc $(printf '%q' "$*")"
}

vm_exists() {
  local host="$1"
  local vmid="$2"

  ssh "$host" "qm status $vmid" &>/dev/null
}

wait_for_ssh() {
  local name="$1"
  local ip="$2"

  echo -n "Waiting for SSH on $name ($ip)... "

  until ssh $SSH_OPTS \
      "${SSH_USER}@${ip}" \
      "echo ok" &>/dev/null; do

    echo -n "."
    sleep 5
  done

  echo "connected"
}

wait_for_os_settle() {
  local name="$1"

  echo -n "Allowing OS to settle on $name... "
  sleep 20
  echo "done"
}

wait_for_rke2_api() {
  local ip="$1"

  echo "Waiting for RKE2 Kubernetes API..."

  until run_ssh "$ip" \
      "sudo /var/lib/rancher/rke2/bin/kubectl \
      --kubeconfig /etc/rancher/rke2/rke2.yaml \
      get nodes" \
      >/dev/null 2>&1; do

    echo "API not ready yet. Retrying in 5 seconds..."
    sleep 5
  done

  echo "Kubernetes API is ready"
}

############################################
# STAGE 1: CREATE VMs
############################################

create_vm() {
  local name="$1"
  local vmid="$2"
  local mac="$3"

  local host="${NODE_HOST_MAP[$name]}"
  local template="${TEMPLATE_MAP[$host]}"

  if vm_exists "$host" "$vmid"; then
    log "$name already exists — skipping"
    return
  fi

  local storage="$NVME_STORAGE"

  local mem

  if [[ "$name" == rancher-control* ]]; then
    mem="$MEMORY_CONTROL"
  else
    mem="$MEMORY_WORKER"
  fi

  log "Creating $name on $host"

  ssh "$host" bash -s <<EOF
set -e

qm clone $template $vmid \
  --name $name \
  --full \
  --storage $storage

qm set $vmid \
  --cores $CPU \
  --memory $mem \
  --cpu x86-64-v2 \
  --net0 virtio,bridge=$BRIDGE,macaddr=$mac \
  --boot c \
  --bootdisk scsi0 \
  --serial0 socket

qm start $vmid
EOF
}

log "STAGE 1: VM CREATION"

create_vm rancher-control1 401 bc:25:11:01:aa:18
create_vm rancher-control2 402 bc:25:11:02:bb:19
create_vm rancher-control3 403 bc:25:11:03:cc:21
create_vm rancher-worker1 404 bc:25:11:04:dd:22
create_vm rancher-worker2 405 bc:25:11:05:ee:23
create_vm rancher-worker3 406 bc:25:11:06:ff:25

############################################
# STAGE 2: WAIT FOR OS
############################################

log "STAGE 2: WAIT FOR OS"

for node in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
  ip="${NODE_IPS[$node]}"

  wait_for_ssh "$node" "$ip"
  wait_for_os_settle "$node"
done

############################################
# STAGE 3: BASE CONFIGURATION
############################################

log "STAGE 3: BASE CONFIGURATION"

for node in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do

  ip="${NODE_IPS[$node]}"

  log "Configuring $node"

  run_ssh "$ip" "

    if ! command -v curl >/dev/null 2>&1; then
      sudo dnf install -y \
        curl \
        nfs-utils \
        iscsi-initiator-utils
    fi

    sudo systemctl enable --now iscsid

    sudo systemctl disable --now firewalld || true

  "
done

############################################
# STAGE 4: CONTROL PLANE
############################################

log "STAGE 4: CONTROL PLANE"

CONTROL1_IP="${NODE_IPS[rancher-control1]}"

for node in "${CONTROL_NODES[@]}"; do

    ip="${NODE_IPS[$node]}"

    log "Checking RKE2 installation on $node"

    if run_ssh "$ip" \
        "sudo test -f /usr/local/bin/rke2"; then

        log "$node already has RKE2 installed — skipping installation"

    else

        log "Installing RKE2 server on $node"

        run_ssh "$ip" \
            "curl -sfL https://get.rke2.io | \
            sudo INSTALL_RKE2_TYPE=server sh"

    fi

    run_ssh "$ip" \
        "sudo mkdir -p /etc/rancher/rke2"

    if [[ "$node" == "rancher-control1" ]]; then

        run_ssh "$ip" "
            sudo tee /etc/rancher/rke2/config.yaml >/dev/null <<EOF
token: $RKE2_TOKEN
tls-san:
  - rancher-control1
  - rancher-control2
  - rancher-control3
EOF
"

    else

        run_ssh "$ip" "
            sudo tee /etc/rancher/rke2/config.yaml >/dev/null <<EOF
server: https://$CONTROL1_IP:9345
token: $RKE2_TOKEN
EOF
"

    fi

    run_ssh "$ip" \
        "sudo systemctl enable --now rke2-server"

    if [[ "$node" == "rancher-control1" ]]; then

        wait_for_rke2_api "$CONTROL1_IP"

    fi

done

############################################
# STAGE 5: WAIT FOR ALL CONTROL-PLANE NODES
############################################

log "STAGE 5: WAIT FOR ALL CONTROL-PLANE NODES"

echo "Waiting for all control-plane nodes to become Ready..."

STAGE5_TIMEOUT=900
STAGE5_INTERVAL=10
STAGE5_ELAPSED=0

while true; do

    echo
    echo "Checking control-plane node readiness..."

    NODE_STATUS=$(run_ssh "$CONTROL1_IP" \
        "sudo /var/lib/rancher/rke2/bin/kubectl \
         --kubeconfig=/etc/rancher/rke2/rke2.yaml \
         get nodes \
         rancher-control1 \
         rancher-control2 \
         rancher-control3 \
         --no-headers" \
        2>&1) || true

    echo "$NODE_STATUS"

    if echo "$NODE_STATUS" | grep -q "rancher-control1.*Ready" &&
       echo "$NODE_STATUS" | grep -q "rancher-control2.*Ready" &&
       echo "$NODE_STATUS" | grep -q "rancher-control3.*Ready"; then

        echo
        echo "All control-plane nodes are Ready."
        break
    fi

    if (( STAGE5_ELAPSED >= STAGE5_TIMEOUT )); then

        echo
        echo "ERROR: Timed out waiting for control-plane nodes."

        run_ssh "$CONTROL1_IP" \
            "sudo /var/lib/rancher/rke2/bin/kubectl \
             --kubeconfig=/etc/rancher/rke2/rke2.yaml \
             get nodes -o wide" || true

        exit 1
    fi

    echo
    echo "Not all control-plane nodes are Ready."
    echo "Retrying in ${STAGE5_INTERVAL} seconds..."
    echo "Elapsed: ${STAGE5_ELAPSED}s / ${STAGE5_TIMEOUT}s"

    sleep "$STAGE5_INTERVAL"

    STAGE5_ELAPSED=$((STAGE5_ELAPSED + STAGE5_INTERVAL))

done

echo
echo "Final control-plane node status:"

run_ssh "$CONTROL1_IP" \
    "sudo /var/lib/rancher/rke2/bin/kubectl \
     --kubeconfig=/etc/rancher/rke2/rke2.yaml \
     get nodes -o wide"


############################################
# STAGE 6: WORKERS
############################################

log "STAGE 6: WORKERS"

for node in "${WORKER_NODES[@]}"; do

  ip="${NODE_IPS[$node]}"

  if run_ssh "$ip" \
      "sudo systemctl cat rke2-agent.service \
      >/dev/null 2>&1"; then

    log "$node already has RKE2 agent installed — skipping installation"

  else

    log "Installing RKE2 agent on $node"

    run_ssh "$ip" \
      "curl -sfL https://get.rke2.io | \
      sudo INSTALL_RKE2_TYPE=agent sh"

  fi

  run_ssh "$ip" \
    "sudo mkdir -p /etc/rancher/rke2"

  run_ssh "$ip" "
    sudo tee /etc/rancher/rke2/config.yaml >/dev/null <<EOF
server: https://$CONTROL1_IP:9345
token: $RKE2_TOKEN
EOF
"

  run_ssh "$ip" \
    "sudo systemctl enable --now rke2-agent"

done

############################################
# STAGE 7: CLUSTER CHECK
############################################

log "STAGE 7: CLUSTER CHECK"

run_ssh "$CONTROL1_IP" \
  "sudo /var/lib/rancher/rke2/bin/kubectl \
  --kubeconfig /etc/rancher/rke2/rke2.yaml \
  get nodes -o wide"

############################################
# CONFIGURE KUBECTL
############################################

log "Configuring kubectl on control node"

run_ssh "$CONTROL1_IP" "

  sudo ln -sf \
    /var/lib/rancher/rke2/bin/kubectl \
    /usr/local/bin/kubectl

  echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' |
    sudo tee /etc/profile.d/rke2-kubectl.sh >/dev/null

  sudo chmod 644 \
    /etc/profile.d/rke2-kubectl.sh

"

############################################
# STAGE 8: INSTALL RANCHER
############################################

log "STAGE 8: INSTALL RANCHER"

run_ssh "$CONTROL1_IP" sudo bash -s <<REMOTE_SCRIPT

set -euo pipefail

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

echo "Waiting for Kubernetes API..."

until /var/lib/rancher/rke2/bin/kubectl get nodes >/dev/null 2>&1; do
  echo "API not ready yet. Retrying in 10 seconds..."
  sleep 10
done

echo "Kubernetes API is available"

echo "Installing Helm if necessary..."

if ! command -v /usr/local/bin/helm >/dev/null 2>&1; then

  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 |
    bash

fi

echo "Adding Rancher and Jetstack Helm repositories..."

/usr/local/bin/helm repo add rancher-latest \
  https://releases.rancher.com/server-charts/latest \
  2>/dev/null || true

/usr/local/bin/helm repo add jetstack \
  https://charts.jetstack.io \
  2>/dev/null || true

/usr/local/bin/helm repo update

echo "Installing cert-manager CRDs..."

/var/lib/rancher/rke2/bin/kubectl apply -f \
  https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.crds.yaml

echo "Installing cert-manager..."

/usr/local/bin/helm upgrade --install cert-manager \
  jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace

echo "Waiting for cert-manager..."

/var/lib/rancher/rke2/bin/kubectl wait \
  --namespace cert-manager \
  --for=condition=Available \
  deployment/cert-manager \
  --timeout=300s

/var/lib/rancher/rke2/bin/kubectl wait \
  --namespace cert-manager \
  --for=condition=Available \
  deployment/cert-manager-webhook \
  --timeout=300s

/var/lib/rancher/rke2/bin/kubectl wait \
  --namespace cert-manager \
  --for=condition=Available \
  deployment/cert-manager-cainjector \
  --timeout=300s

echo "Installing Rancher..."

/usr/local/bin/helm upgrade --install rancher \
  rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname="$RANCHER_HOSTNAME" \
  --set bootstrapPassword="$RANCHER_BOOTSTRAP_PASSWORD" \
  --set replicas=1

echo "Waiting for Rancher..."

/var/lib/rancher/rke2/bin/kubectl -n cattle-system rollout status \
  deployment/rancher \
  --timeout=600s

echo "Rancher installation complete"

/var/lib/rancher/rke2/bin/kubectl get pods -n cattle-system
/var/lib/rancher/rke2/bin/kubectl get ingress -n cattle-system

REMOTE_SCRIPT

############################################
# STAGE 9: INSTALL NFS CSI DRIVER
############################################

log "STAGE 9: INSTALL NFS CSI DRIVER"

run_ssh "$CONTROL1_IP" sudo bash -s <<REMOTE_SCRIPT

set -euo pipefail

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

echo "Installing Kubernetes CSI NFS driver..."

/usr/local/bin/helm repo add csi-driver-nfs \
  https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts \
  2>/dev/null || true

/usr/local/bin/helm repo update

/usr/local/bin/helm upgrade --install csi-driver-nfs \
  csi-driver-nfs/csi-driver-nfs \
  --namespace kube-system \
  --set kubeletDir=/var/lib/kubelet

echo "Waiting for NFS CSI driver..."

sleep 30

/var/lib/rancher/rke2/bin/kubectl get pods -n kube-system

REMOTE_SCRIPT

############################################
# STAGE 10: CREATE NFS STORAGE CLASS
############################################

log "STAGE 10: CREATE NFS STORAGE CLASS"

run_ssh "$CONTROL1_IP" sudo bash -s <<REMOTE_SCRIPT

set -euo pipefail

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

cat <<EOF | /var/lib/rancher/rke2/bin/kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: $NFS_SERVER
  share: $NFS_SHARE
reclaimPolicy: Retain
volumeBindingMode: Immediate
mountOptions:
  - hard
  - nfsvers=4.1
EOF

/var/lib/rancher/rke2/bin/kubectl get storageclass nfs-csi

REMOTE_SCRIPT

############################################
# STAGE 11: TEST NFS PROVISIONING
############################################

log "STAGE 11: TEST NFS PROVISIONING"

run_ssh "$CONTROL1_IP" sudo bash -s <<REMOTE_SCRIPT

set -euo pipefail

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

cat <<EOF | /var/lib/rancher/rke2/bin/kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  storageClassName: nfs-csi
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 5Gi
EOF

echo "Waiting for PVC to bind..."

/var/lib/rancher/rke2/bin/kubectl wait \
  --for=jsonpath='{.status.phase}'=Bound \
  pvc/my-pvc \
  --timeout=180s

/var/lib/rancher/rke2/bin/kubectl get pvc my-pvc

REMOTE_SCRIPT

############################################
# FINAL VALIDATION
############################################

log "FINAL VALIDATION"

run_ssh "$CONTROL1_IP" sudo bash -s <<REMOTE_SCRIPT

set -euo pipefail

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

echo
echo "=== NODES ==="
/var/lib/rancher/rke2/bin/kubectl get nodes -o wide

echo
echo "=== STORAGE CLASSES ==="
/var/lib/rancher/rke2/bin/kubectl get storageclass

echo
echo "=== PVCs ==="
/var/lib/rancher/rke2/bin/kubectl get pvc -A

echo
echo "=== RANCHER ==="
/var/lib/rancher/rke2/bin/kubectl get pods -n cattle-system

echo
echo "=== NFS CSI ==="
/var/lib/rancher/rke2/bin/kubectl get pods -n kube-system

REMOTE_SCRIPT

log "CLUSTER BUILD COMPLETE"

echo
echo "Rancher hostname:"
echo "  $RANCHER_HOSTNAME"
echo
echo "Rancher bootstrap password:"
echo "  $RANCHER_BOOTSTRAP_PASSWORD"
echo
