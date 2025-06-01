#!/bin/bash

YELLOW='\033[1;33m'
NC='\033[0m'

PROXMOX_HOST="root@dell-server"

for VMID in {109..117}; do
  echo -e "${YELLOW}Destroying VM $VMID...${NC}"
  ssh $PROXMOX_HOST "qm stop $VMID --timeout 10 2>/dev/null; qm destroy $VMID --purge 2>/dev/null"
done
echo -e "${YELLOW}Cleaning up old config files${NC}"
rm /home/smarz/talos/controlplane.yaml --force
rm /home/smarz/talos/kubeconfig --force
rm /home/smarz/talos/talosconfig --force
rm /home/smarz/talos/worker.yaml --force
rm /home/smarz/talos/sc-nfs.yaml --force
rm /home/smarz/talos/pvc-nfs.yaml --force
