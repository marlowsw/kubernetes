# Kubernetes Infrastructure Automation

Automated Kubernetes cluster provisioning scripts for building Rancher-managed Kubernetes environments on Proxmox using RKE2.

This repository contains automation for creating reproducible Kubernetes clusters including:

- Proxmox VM provisioning
- RKE2 Kubernetes installation
- High availability control plane
- Worker node deployment
- Rancher installation
- cert-manager installation
- NFS CSI storage integration
- Cluster cleanup and rebuild workflows

The goal of this project is to quickly create disposable, repeatable Kubernetes environments for testing, learning, and homelab infrastructure.

---

# Repository Structure

```
kubernetes/
|
├── rancher/
│   ├── rancher-build.sh
│   ├── rancher-cleanup.sh
│   ├── rancher-full-cleanup.sh
│   └── rancher-full.sh
|
├── rocky-k8s/
│   ├── containerd.sh
│   └── kubetools.sh
|
└── talos/
    ├── deploy.sh
    ├── destroy.sh
    └── README.md
```

---

# Rancher RKE2 Cluster Architecture

The default deployment creates:

                Rancher UI
                   |
                   |
          +----------------+
          | RKE2 Cluster   |
          +----------------+

    Control Plane (HA)

    +----------------+
    | rancher-control1 |
    +----------------+

    +----------------+
    | rancher-control2 |
    +----------------+

    +----------------+
    | rancher-control3 |
    +----------------+


         Workers

    +----------------+
    | rancher-worker1 |
    +----------------+

    +----------------+
    | rancher-worker2 |
    +----------------+

    +----------------+
    | rancher-worker3 |
    +----------------+


          Storage

    NFS Server
        |
        |
    NFS CSI Driver
        |
    Kubernetes PVCs

---

# Features

## Automated VM Deployment

The cluster builder:

- clones VMs from a Proxmox template
- assigns CPU and memory
- configures networking
- waits for SSH availability
- prepares operating systems

Example:


rancher-control1
rancher-control2
rancher-control3

rancher-worker1
rancher-worker2
rancher-worker3


---

## Kubernetes Installation

The deployment automatically installs:

- RKE2 Server nodes
- RKE2 Agent nodes
- Kubernetes API
- kubeconfig configuration
- Helm

---

## Rancher Installation

The script installs:

- cert-manager
- Rancher Helm chart
- cattle-system namespace

After deployment:


kubectl get pods -n cattle-system


should show Rancher running.

---

## Storage

The cluster installs:

- Kubernetes NFS CSI Driver
- NFS StorageClass
- Test PersistentVolumeClaim

StorageClass:


nfs-csi


Example:

```yaml
storageClassName: nfs-csi
accessModes:
  - ReadWriteMany
Requirements
Proxmox

Required:

Proxmox VE
VM template containing Rocky Linux
SSH access
cloud-init configured
network bridge configured

Example:

vmbr0
Kubernetes Nodes

Default sizing:

Node Type	CPU	Memory
Control Plane	4 cores	8GB
Worker	4 cores	16GB

Configured in:

rancher/rancher-full.sh
Network

The default deployment expects:

Network:
10.0.0.0/24

Nodes:

Node	IP
rancher-control1	10.0.0.249
rancher-control2	10.0.0.244
rancher-control3	10.0.0.235
rancher-worker1	10.0.0.204
rancher-worker2	10.0.0.222
rancher-worker3	10.0.0.205
Deploy Cluster

Clone repository:

git clone <repository-url>

cd kubernetes/rancher

Run:

./rancher-full.sh

The script performs:

1. Create Proxmox VMs
2. Configure operating system
3. Install RKE2 control plane
4. Join additional control nodes
5. Install worker nodes
6. Install Rancher
7. Install NFS CSI
8. Validate cluster
Verify Cluster

SSH to the first control plane node:

ssh smarz@10.0.0.249

Check nodes:

kubectl get nodes -o wide

Expected:

NAME                 STATUS   ROLES
rancher-control1     Ready    control-plane,etcd
rancher-control2     Ready    control-plane,etcd
rancher-control3     Ready    control-plane,etcd
rancher-worker1      Ready    <none>
rancher-worker2      Ready    <none>
rancher-worker3      Ready    <none>
Adding Additional Worker Nodes

To add another worker:

1. Add the worker name

Edit:

rancher/rancher-full.sh

Add:

WORKER_NODES=(
  rancher-worker1
  rancher-worker2
  rancher-worker3
  rancher-worker4
)
2. Add Proxmox mapping

Add:

declare -A NODE_HOST_MAP=(
  [rancher-worker4]=$PROXMOX_HOST1
)
3. Add IP address

Add:

declare -A NODE_IPS=(
  [rancher-worker4]=10.0.0.206
)
4. Create the VM

Add a VM creation block:

create_vm rancher-worker4 407 aa:bb:cc:dd:ee:ff

Update:

VM ID
MAC address
IP reservation
5. Run deployment

Run:

./rancher-full.sh

The script is idempotent and skips existing nodes.

Verify:

kubectl get nodes
Adding Additional Control Plane Nodes

Control plane nodes use RKE2 server mode.

Add:

CONTROL_NODES=(
 rancher-control1
 rancher-control2
 rancher-control3
 rancher-control4
)

Add:

rancher-control4

to:

NODE_HOST_MAP
NODE_IPS
VM creation section

The node will automatically join:

server: https://rancher-control1:9345
token: <cluster-token>
Changing Cluster Resources

Edit:

rancher/rancher-full.sh

CPU:

CPU=4

Control plane memory:

MEMORY_CONTROL=8192

Worker memory:

MEMORY_WORKER=16384

Example:

Increase workers:

MEMORY_WORKER=32768
CPU=8
Changing Storage

The default NFS configuration:

NFS_SERVER="10.0.0.9"

NFS_SHARE="/Volume2/proxmox/k8s"

Modify:

NFS_SERVER="<new-server-ip>"

NFS_SHARE="<new-export>"

The script will recreate:

StorageClass:
 nfs-csi
Cluster Cleanup

⚠️ WARNING:

This permanently deletes the cluster VMs.

Run:

./rancher-full-cleanup.sh

The cleanup removes:

Proxmox VMs
RKE2 installation
Kubernetes state
CNI configuration
kubelet data
