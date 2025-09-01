#!/bin/bash

# Colors
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Proxmox host
PROXMOX="root@dell-server"

# VMs to remove (your rancher nodes)
VM_IDS=(401 402 403 404 405 406)

echo -e "${YELLOW}Cleaning up Rancher VMs...${NC}"

for vmid in "${VM_IDS[@]}"; do
    echo -e "${YELLOW}Stopping and destroying VM $vmid...${NC}"
    ssh $PROXMOX bash -s <<EOF
if qm status $vmid &>/dev/null; then
    qm stop $vmid --skiplock || true
    qm destroy $vmid --purge --skiplock || true
else
    echo "VM $vmid does not exist, skipping."
fi
EOF
done

echo -e "${YELLOW}Cleanup complete. Template VM 100 was left untouched.${NC}"

