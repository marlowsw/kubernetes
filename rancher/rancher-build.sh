#!/bin/bash

# Colors
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Nodes
CONTROL_NODES=(rancher-control1 rancher-control2 rancher-control3)
WORKER_NODES=(rancher-worker1 rancher-worker2 rancher-worker3)

# Proxmox host
PROXMOX="root@dell-server"

# Configurations
TEMPLATE_ID=100          # VMID of your rocky-template
DISK_STORAGE="NVME-NFS-Image"
CPU=4
MEMORY=8192
BRIDGE="vmbr0"

# === Clone VM function ===
clone_vm() {
    local vmid=$1
    local name=$2
    local macaddr=$3

    echo -e "${YELLOW}Cloning VM $name ($vmid) from template $TEMPLATE_ID...${NC}"

    ssh $PROXMOX bash -s <<EOF
set -e

# Clone from rocky-template
qm clone $TEMPLATE_ID $vmid --name $name --full --storage $DISK_STORAGE

# Configure VM
qm set $vmid \
    --cores $CPU --sockets 1 \
    --memory $MEMORY \
    --net0 virtio,bridge=$BRIDGE,macaddr=$macaddr \
    --boot c --bootdisk scsi0 \
    --serial0 socket

# Cloud-Init: set user + SSH key + DHCP (REMOVED CONFIG FOR BUILD)
#qm set $vmid --ciuser root --sshkey ~/.ssh/id_rsa.pub --ipconfig0 ip=dhcp

# Start VM
qm start $vmid
EOF
}

# === Node creation ===
echo -e "${YELLOW}Creating control-plane nodes...${NC}"
clone_vm 401 "rancher-control1" bc:25:11:01:aa:18
clone_vm 402 "rancher-control2" bc:25:11:02:bb:19
clone_vm 403 "rancher-control3" bc:25:11:03:cc:21

echo -e "${YELLOW}Creating worker nodes...${NC}"
clone_vm 404 "rancher-worker1" bc:25:11:04:dd:22
clone_vm 405 "rancher-worker2" bc:25:11:05:ee:23
clone_vm 406 "rancher-worker3" bc:25:11:06:ff:25

# 401 - 10.0.0.249 
# 402 - 10.0.0.244
# 403 - 10.0.0.235
# 404 - 10.0.0.204
# 405 - 10.0.0.222
# 406 - 10.0.0.205

echo -e "${YELLOW}Waiting for VMs to be ready via SSH...${NC}"

# List of all nodes
ALL_NODES=("${CONTROL_NODES[@]}" "${WORKER_NODES[@]}")

for NODE in "${ALL_NODES[@]}"; do
    echo -e "${YELLOW}Waiting for $NODE to be reachable...${NC}"
    # Keep trying until SSH succeeds
    until ssh $PROXMOX "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no root@$NODE 'echo ready'" &>/dev/null; do
        echo -n "."
        sleep 5
    done
    echo " $NODE is ready!"
done

echo -e "${YELLOW}All VMs are reachable via SSH.${NC}"

# Common OS setup
COMMON_CMDS=$(cat <<'EOC'
systemctl disable --now firewalld
dnf install -y nfs-utils cryptsetup iscsi-initiator-utils
systemctl enable --now iscsid.service
dnf update -y
dnf clean all
EOC
)

echo -e "${YELLOW}Applying common OS setup to all nodes...${NC}"
for NODE in "${CONTROL_NODES[@]}" "${WORKER_NODES[@]}"; do
    ssh $PROXMOX "ssh root@$NODE '$COMMON_CMDS'"
done

# RKE2 installation on control nodes
RKE2_TOKEN="bootstrapAllTheThings"
CONTROL1_IP="10.0.0.249"  # adjust if needed
for NODE in "${CONTROL_NODES[@]}"; do
    echo -e "${YELLOW}Installing RKE2 server on $NODE...${NC}"
    ssh $PROXMOX "ssh root@$NODE 'curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=server sh'"
    ssh $PROXMOX "ssh root@$NODE 'mkdir -p /etc/rancher/rke2/'"

    if [[ "$NODE" == "rancher-control1" ]]; then
        # Bootstrap node – no server: line
        ssh $PROXMOX "ssh root@$NODE 'cat <<EOF >/etc/rancher/rke2/config.yaml
token: $RKE2_TOKEN
tls-san:
  - rancher-control1.homelab.home
  - rancher-control2.homelab.home
  - rancher-control3.homelab.home
EOF'"
    else
        # Joining control-plane nodes – needs server: line
        ssh $PROXMOX "ssh root@$NODE 'cat <<EOF >/etc/rancher/rke2/config.yaml
server: https://$CONTROL1_IP:9345
token: $RKE2_TOKEN
tls-san:
  - rancher-control1.homelab.home
  - rancher-control2.homelab.home
  - rancher-control3.homelab.home
EOF'"
    fi

    ssh $PROXMOX "ssh root@$NODE 'systemctl enable --now rke2-server.service'"
done

# Wait for first control node to be active
echo -e "${YELLOW}Waiting for RKE2 server on ${CONTROL_NODES[0]}...${NC}"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'while ! systemctl is-active --quiet rke2-server; do sleep 10; done'"

# Symlink kubectl and set KUBECONFIG
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'ln -s \$(find /var/lib/rancher/rke2/data/ -name kubectl) /usr/local/bin/kubectl'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'echo \"export KUBECONFIG=/etc/rancher/rke2/rke2.yaml PATH=\$PATH:/usr/local/bin/:/var/lib/rancher/rke2/bin/\" >> ~/.bashrc && source ~/.bashrc'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'kubectl get nodes'"

# RKE2 agents on worker nodes
RANCHER1_IP="10.0.0.249"  # first control node IP
for NODE in "${WORKER_NODES[@]}"; do
    echo -e "${YELLOW}Installing RKE2 agent on $NODE...${NC}"
    ssh $PROXMOX "ssh root@$NODE 'export RANCHER1_IP=$RANCHER1_IP && curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent sh'"
    ssh $PROXMOX "ssh root@$NODE 'mkdir -p /etc/rancher/rke2/'"
    ssh $PROXMOX "ssh root@$NODE 'cat <<EOF >/etc/rancher/rke2/config.yaml
server: https://$RANCHER1_IP:9345
token: $RKE2_TOKEN
EOF'"
    ssh $PROXMOX "ssh root@$NODE 'systemctl enable --now rke2-agent.service'"
done

# Helm & Rancher installation on first control node
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'curl -#L https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'helm repo add jetstack https://charts.jetstack.io --force-update'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'helm upgrade -i cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true'"
ssh $PROXMOX "ssh root@${CONTROL_NODES[0]} 'helm upgrade -i rancher rancher-latest/rancher --create-namespace --namespace cattle-system --set hostname=rancher.$RANCHER1_IP.sslip.io --set bootstrapPassword=bootStrapAllTheThings --set replicas=1'"

echo -e "${YELLOW}Post-provision setup complete.${NC}"
