terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

locals {
  # Built by templates/build-debian13.sh; local-lvm isn't shared, so each node has its own copy.
  template_ids = { moltres = 9000, zapdos = 9001, articuno = 9002 }
  ip           = "192.168.20.${var.host}"
}

resource "proxmox_virtual_environment_vm" "this" {
  name            = var.name
  node_name       = var.node_name
  stop_on_destroy = true

  clone {
    vm_id = local.template_ids[var.node_name]
    full  = true
  }

  # Match the template (UEFI, q35); otherwise the provider falls back to SeaBIOS/i440fx defaults.
  bios          = "ovmf"
  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = false
  }

  operating_system {
    type = "l26"
  }

  # Installed on first boot by the vendor-data snippet; needed for consistent (fs-frozen) vzdump backups and clean shutdowns.
  agent {
    enabled = true
    trim    = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_gb
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = 20
  }

  initialization {
    datastore_id        = "local-lvm"
    vendor_data_file_id = "local:snippets/qga-vendor.yaml" # written by templates/build-debian13.sh
    ip_config {
      ipv4 {
        address = "${local.ip}/24"
        gateway = "192.168.20.1"
      }
    }
    dns {
      servers = ["192.168.10.4"]
    }
    user_account {
      username = "debian"
      keys     = var.ssh_public_keys
    }
  }
}
