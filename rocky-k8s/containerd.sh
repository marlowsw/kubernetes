#!/bin/bash
# Rocky Linux container runtime setup script
# Safe and compatible with kubeadm + containerd

# Platform detection
[ "$(arch)" = "aarch64" ] && PLATFORM="arm64"
[ "$(arch)" = "x86_64" ] && PLATFORM="amd64"

# OS detection
MYOS=$(awk -F= '/^ID=/{print $2}' /etc/os-release | tr -d '"')

if [[ "$MYOS" == "rocky" || "$MYOS" == "rhel" || "$MYOS" == "centos" ]]; then
    echo "✅ Detected Rocky-compatible system: $MYOS"

    # Install base dependencies
    sudo dnf install -y jq curl wget tar yum-utils device-mapper-persistent-data lvm2

    # Enable required kernel modules
    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

    sudo modprobe overlay
    sudo modprobe br_netfilter

    # Configure sysctl parameters
    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    sudo sysctl --system

    # Add Docker's containerd repo
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

    # Install containerd from Docker repo
    sudo dnf install -y containerd.io

    # Clean up any old/conflicting binaries from GitHub installs
    sudo rm -f /usr/local/bin/containerd*
    sudo rm -f /usr/local/bin/ctr
    sudo rm -f /usr/local/sbin/runc

    # Generate clean default config
    sudo mkdir -p /etc/containerd
    containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

    # Set SystemdCgroup = true
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # (Optional) Install latest runc binary
    RUNC_VERSION=$(curl -s https://api.github.com/repos/opencontainers/runc/releases/latest | jq -r '.tag_name')
    wget https://github.com/opencontainers/runc/releases/download/${RUNC_VERSION}/runc.${PLATFORM}
    sudo install -m 755 runc.${PLATFORM} /usr/local/sbin/runc

    # Start and enable containerd
    sudo systemctl daemon-reexec
    sudo systemctl enable --now containerd

    echo "✅ containerd installed and running."

    # Marker for kubeadm install
    touch /tmp/container.txt

else
    echo "❌ Unsupported OS: $MYOS. This script is intended for Rocky Linux only."
    exit 1
fi

