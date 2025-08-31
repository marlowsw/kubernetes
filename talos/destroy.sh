#!/bin/bash

YELLOW='\033[1;33m'
NC='\033[0m'

# Define hosts and their VMID ranges
declare -A HOST_RANGES
HOST_RANGES["root@mini1"]="107 108 202 203"
HOST_RANGES["root@mini2"]="109 201 302 303"
HOST_RANGES["root@mini3"]="301 401 402 403"
#HOST_RANGES["root@mini3"]="401..403"

for HOST in "${!HOST_RANGES[@]}"; do
  RANGE=${HOST_RANGES[$HOST]}
   for VMID in $RANGE; do
    echo -e "${YELLOW}[$HOST] Destroying VM $VMID...${NC}"
    ssh $HOST "qm stop $VMID --timeout 10 2>/dev/null; qm destroy $VMID --purge 2>/dev/null"
  done
done

echo -e "${YELLOW}Cleaning up old config files${NC}"
rm -f /home/smarz/talos/controlplane.yaml \
      /home/smarz/talos/kubeconfig \
      /home/smarz/talos/talosconfig \
      /home/smarz/talos/worker.yaml \
      /home/smarz/talos/sc-nfs.yaml \
      /home/smarz/talos/pvc-nfs.yaml
