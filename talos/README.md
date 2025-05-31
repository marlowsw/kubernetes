# Talos Cluster Scripts
# Prerequisites
- DHCP/DNS server- I'm running pfsense and a bind9 docker deployment
- admin node- I use an ubuntu 24.04 VM configured with packages for managing kubernetes
  - packages: homebrew(brew), kubectl, talosctl(brew) & k9s(optional downloaded via brew) 

Scripts to deploy and destroy Talos-based Kubernetes clusters on Proxmox.

- `deploy.sh` – Creates VMs and applies Talos configs
- `destroy.sh` – Destroys the Talos VMs and cleans up configs
