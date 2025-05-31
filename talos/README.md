# Talos Cluster Deployment
# Prerequisites
- DHCP/DNS server- I'm running pfsense and a bind9 docker deployment
- admin node- I use an ubuntu 24.04 VM configured with packages for managing kubernetes
  - packages: homebrew(brew), kubectl, talosctl(brew) & k9s(optional downloaded via brew) 

Scripts to deploy and destroy Talos-based Kubernetes clusters on Proxmox.

- `deploy.sh` – Creates VMs and applies Talos configs
- `destroy.sh` – Destroys the Talos VMs and cleans up configs

DHCP Reservations:
![image](https://github.com/user-attachments/assets/2bb1ec4b-9317-4685-9883-910c304dd179)
> **Make sure to configure the DHCP DNS section to the correct IP of your DNS server**

### DNS:
<pre>
talos-control-1     IN A      10.0.0.155

talos-control-2     IN A      10.0.0.131

talos-control-3     IN A      10.0.0.132

talos-worker-1      IN A      10.0.0.133

talos-worker-2      IN A      10.0.0.139

talos-worker-3      IN A      10.0.0.135

talos-test-1        IN A      10.0.0.136

talos-test-2        IN A      10.0.0.137

talos-test-3        IN A      10.0.0.138 </pre>


### Admin node:

- **kubectl install**:  
  https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-using-native-package-management

- **Homebrew install**:  
  https://brew.sh/  
  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

k9s install: brew install k9s

talosctl install: brew install talosctl

###Install
- clone repo
- cd talos
- ./deploy.sh (make sure the directory structure matches your environment)
- kubectl get nodes (once the script finishes it can take 5 minutes for the cluster to be ready)

If you see "No resources found" just give it a couple of minutes!

@admin1:~/talos$ kubectl get nodes

No resources found

<pre>@admin1:~/talos$ kubectl get nodes

NAME              STATUS   ROLES           AGE     VERSION

talos-control-1   Ready    control-plane   3m47s   v1.33.1

talos-control-2   Ready    control-plane   3m42s   v1.33.1

talos-control-3   Ready    control-plane   3m44s   v1.33.1

talos-test-1      Ready    <none>          3m56s   v1.33.1

talos-test-2      Ready    <none>          4m8s    v1.33.1

talos-test-3      Ready    <none>          3m49s   v1.33.1

talos-worker-1    Ready    <none>          3m53s   v1.33.1

talos-worker-2    Ready    <none>          4m9s    v1.33.1

talos-worker-3    Ready    <none>          3m40s   v1.33.1 </pre>
