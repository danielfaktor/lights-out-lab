#!/usr/bin/env bash
# Build a Debian 13 cloud-init template on one Proxmox node. Runs locally; ssh's to the node.
# Usage: templates/build-debian13.sh <node-ip> <vmid>   e.g. 192.168.10.6 9000
set -euo pipefail
node=${1:?node ip}; vmid=${2:?vmid}
ssh -o IdentityAgent="${SSH_AUTH_SOCK}" "root@${node}" bash -s -- "$vmid" <<'REMOTE'
set -euo pipefail
vmid=$1
base=https://cloud.debian.org/images/cloud/trixie/latest
img=debian-13-genericcloud-amd64.qcow2
# Vendor-data snippet: installs qemu-guest-agent on first boot (Debian's cloud image doesn't ship it).
# local is per-node storage, so each node needs its own copy. The module points vendor_data_file_id at it.
mkdir -p /var/lib/vz/snippets
cat > /var/lib/vz/snippets/qga-vendor.yaml <<'YAML'
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - [systemctl, enable, --now, qemu-guest-agent]
YAML
content=$(pvesh get /storage/local --output-format json | python3 -c 'import json,sys;print(json.load(sys.stdin)["content"])')
case ",$content," in *,snippets,*) ;; *) pvesm set local --content "$content,snippets" ;; esac
if qm status "$vmid" >/dev/null 2>&1; then echo "$(hostname): VMID $vmid exists, snippet refreshed"; exit 0; fi
cd /var/lib/vz/template
curl -fsSLO "$base/$img"
curl -fsSL "$base/SHA512SUMS" | grep " $img\$" | sha512sum -c -
qm create "$vmid" --name debian13-tmpl --ostype l26 --machine q35 --bios ovmf \
  --cpu host --cores 2 --memory 2048 --net0 virtio,bridge=vmbr0 \
  --scsihw virtio-scsi-single --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0 \
  --scsi0 "local-lvm:0,import-from=/var/lib/vz/template/$img,discard=on,ssd=1" \
  --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
qm template "$vmid"
rm -f "/var/lib/vz/template/$img"
echo "$(hostname): template $vmid ready"
REMOTE
