terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.122"
    }
  }
}

provider "proxmox" {
  insecure = true
}

locals {
  image = "docker.io/technitium/dns-server:15.6.2"
  servers = {
    dns1 = { node = "moltres", host = 2 }
    dns2 = { node = "zapdos", host = 3 }
  }
}

resource "proxmox_oci_image" "technitium" {
  for_each     = local.servers
  node_name    = each.value.node
  datastore_id = "local"
  reference    = local.image
}

resource "proxmox_virtual_environment_container" "dns" {
  for_each      = local.servers
  node_name     = each.value.node
  unprivileged  = true
  start_on_boot = true

  operating_system {
    template_file_id = proxmox_oci_image.technitium[each.key].id
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    size         = 4
  }

  network_interface {
    name         = "eth0"
    bridge       = "vmbr0"
    vlan_id      = 20
    host_managed = true
  }

  initialization {
    hostname   = each.key
    entrypoint = "/usr/bin/dotnet /opt/technitium/dns/DnsServerApp.dll /etc/dns"
    ip_config {
      ipv4 {
        address = "192.168.20.${each.value.host}/24"
        gateway = "192.168.20.1"
      }
    }
  }

  lifecycle {
    ignore_changes = [environment_variables, console]
  }
}

output "servers" {
  value = { for k, ct in proxmox_virtual_environment_container.dns : k => { id = ct.vm_id, ip = "192.168.20.${local.servers[k].host}" } }
}
