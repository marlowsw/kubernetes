#!/bin/bash

set -euo pipefail

############################################
# CONFIG
############################################

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

PROXMOX_HOST1="root@nas1"

declare -A NODE_VMIDS=(
  [rancher-control1]=401
  [rancher-control2]=402
  [rancher-control3]=403
  [rancher-worker1]=404
  [rancher-worker2]=405
  [rancher-worker3]=406
)

declare -A NODE_IPS=(
  [rancher-control1]=10.0.0.249
  [rancher-control2]=10.0.0.244
  [rancher-control3]=10.0.0.235
  [rancher-worker1]=10.0.0.204
  [rancher-worker2]=10.0.0.222
  [rancher-worker3]=10.0.0.205
)

############################################
# HELPERS
############################################

log() {
    echo -e "\n==== $1 ====\n"
}

confirm() {
    read -rp "Type DELETE to continue: " answer
    [[ "$answer" == "DELETE" ]]
}

vm_exists() {
    ssh $PROXMOX_HOST1 "qm status $1" &>/dev/null
}

############################################
# WARNING
############################################

echo "
==========================================
 RKE2 Rancher Cluster Cleanup

 This will DELETE:

 - rancher-control1 (401)
 - rancher-control2 (402)
 - rancher-control3 (403)
 - rancher-worker1  (404)
 - rancher-worker2  (405)
 - rancher-worker3  (406)

 INCLUDING ALL VM DISKS

==========================================
"

confirm || {
    echo "Aborted"
    exit 1
}


############################################
# STAGE 1: STOP VMS
############################################

log "Stopping VMs"

for node in "${!NODE_VMIDS[@]}"; do

    vmid=${NODE_VMIDS[$node]}

    if vm_exists $vmid; then
        echo "Stopping $node ($vmid)"
        ssh $PROXMOX_HOST1 "
            qm stop $vmid --skiplock || true
        "
    else
        echo "$node does not exist"
    fi

done


############################################
# STAGE 2: REMOVE VMS
############################################

log "Destroying VMs"

for node in "${!NODE_VMIDS[@]}"; do

    vmid=${NODE_VMIDS[$node]}

    if vm_exists $vmid; then

        echo "Destroying $node ($vmid)"

        ssh $PROXMOX_HOST1 "
            qm destroy $vmid --purge
        "

    fi

done


############################################
# STAGE 3: CLEAN RKE2 DATA
############################################

log "Cleaning leftover RKE2 state"

for node in "${!NODE_IPS[@]}"; do

    ip=${NODE_IPS[$node]}

    echo "Checking $node ($ip)"

    if ssh $SSH_OPTS smarz@$ip "echo ok" &>/dev/null; then

        ssh $SSH_OPTS smarz@$ip <<'EOF'

sudo systemctl stop rke2-server 2>/dev/null || true
sudo systemctl stop rke2-agent 2>/dev/null || true

sudo /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true

sudo rm -rf /etc/rancher/rke2
sudo rm -rf /var/lib/rancher/rke2
sudo rm -rf /var/lib/kubelet
sudo rm -rf /etc/cni
sudo rm -rf /opt/cni

EOF

    else
        echo "$node unreachable, skipping OS cleanup"
    fi

done


############################################
# STAGE 4: VERIFY
############################################

log "Verification"

ssh $PROXMOX_HOST1 "
qm list | grep -E '40[1-6]' || echo 'No cluster VMs remain'
"


log "CLEANUP COMPLETE"
