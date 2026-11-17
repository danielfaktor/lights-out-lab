# source env.sh — loads the Proxmox API token from the macOS Keychain (never stored in the repo).
# Cluster VIP (keepalived), not pve.danielfaktor.net: NPM and DNS are moving onto this cluster, so the API must not depend on them.
export PROXMOX_VE_ENDPOINT="https://192.168.10.9:8006/"
secret=$(security find-generic-password -s proxmox-terraform -w) || { echo "env.sh: no 'proxmox-terraform' item in Keychain (or Keychain locked)" >&2; return 1; }
export PROXMOX_VE_API_TOKEN="terraform@pve!homelab=${secret}"
unset secret
