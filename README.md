# Kubernetes Infrastructure Automation

A collection of scripts and automation used to build, manage, and experiment with Kubernetes clusters across multiple platforms.

This repository contains infrastructure automation for:

- Rancher + RKE2 Kubernetes clusters on Proxmox
- Talos Kubernetes deployments
- Rocky Linux Kubernetes node preparation tools
- Container runtime and cluster utility scripts

The goal of this repository is to provide repeatable workflows for creating Kubernetes environments for homelab, testing, and learning.

---

# Repository Structure

```
kubernetes/
|
├── rancher/
│   └── Rancher RKE2 cluster automation
|
├── rocky-k8s/
│   └── Rocky Linux Kubernetes node utilities
|
└── talos/
    └── Talos Kubernetes automation
```

---

# Projects

## Rancher / RKE2

Directory:

```
rancher/
```

Automates deployment of a Rancher-managed RKE2 Kubernetes cluster.

Features:

- Proxmox VM creation
- RKE2 control plane deployment
- RKE2 worker node deployment
- High availability control plane
- Rancher installation
- cert-manager installation
- NFS CSI storage integration
- Cluster cleanup workflows

See:

```
rancher/README.md
```

for deployment instructions.

---

## Rocky Linux Kubernetes Tools

Directory:

```
rocky-k8s/
```

Utility scripts for preparing Rocky Linux systems for Kubernetes workloads.

Includes:

- containerd installation/configuration
- Kubernetes tooling installation
- node preparation helpers

---

## Talos Kubernetes

Directory:

```
talos/
```

Automation for deploying and managing Talos Linux Kubernetes clusters.

Features:

- Cluster deployment
- Cluster teardown
- Talos configuration workflows

See:

```
talos/README.md
```

for details.

---

# Requirements

These projects are designed around:

- Proxmox Virtual Environment
- Linux systems
- Kubernetes
- RKE2
- Talos Linux
- Helm
- kubectl

---

# Design Goals

This repository focuses on:

- repeatable infrastructure builds
- infrastructure-as-code practices
- disposable Kubernetes environments
- automation over manual configuration
- learning and experimentation with Kubernetes platforms

---

# Future Improvements

Potential additions:

- Terraform Proxmox automation
- Ansible configuration management
- GitOps bootstrapping
- Monitoring stack deployment
- Automated backups
- Cluster lifecycle management

---

# License

Provided for educational and homelab use.

Use at your own risk.
