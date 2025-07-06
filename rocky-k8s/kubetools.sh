#!/bin/bash
# Modified for Rocky Linux based on:
# https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/

# Prerequisite check
if ! [ -f /tmp/container.txt ]; then
    echo "Please run ./setup-container.sh before running this script."
    exit 4
fi

# Detect OS
MYOS=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')

# Get Kubernetes version (drop patch number)
KUBEVERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | jq -r '.tag_name')
KUBEVERSION=${KUBEVERSION%.*}

if [[ "$MYOS" == "rocky" || "$MYOS" == "rhel" || "$MYOS" == "centos" ]]; then
    echo "Running Rocky Linux configuration..."

    # Enable br_netfilter
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

    sudo modprobe br_netfilter

    # Set sysctl params
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
EOF

    sudo sysctl --system

    # Install dependencies
    sudo dnf install -y curl gnupg2 wget jq
    sudo dnf install -y yum-utils

    # Add Kubernetes repo
    sudo tee /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBEVERSION}/rpm/repodata/repomd.xml.key
EOF

    # Disable SELinux (optional but common)
    sudo setenforce 0
    sudo sed -i --follow-symlinks 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    # Disable swap
    sudo swapoff -a
    sudo sed -i '/swap/d' /etc/fstab

    # Install Kubernetes tools
    sudo dnf install -y kubelet kubeadm kubectl
    sudo systemctl enable --now kubelet
    sudo dnf mark install kubelet kubeadm kubectl

else
    echo "This script currently supports Rocky Linux or RHEL-based systems only."
    exit 1
fi

# Set container runtime socket
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

# Final instructions
echo "✅ kubeadm installation complete."
echo "👉 After initializing the control plane, run:"
echo "   kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
echo "👉 On worker nodes, join using the kubeadm join command from the control plane."

