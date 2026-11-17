export PROXMOX_VE_ENDPOINT="https://192.168.10.9:8006/"
secret=$(security find-generic-password -s proxmox-terraform -w) || { echo "env.sh: no 'proxmox-terraform' item in Keychain (or Keychain locked)" >&2; return 1; }
export PROXMOX_VE_API_TOKEN="terraform@pve!homelab=${secret}"
unset secret
