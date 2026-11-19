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

# Log collector: receives router syslog, pulls DNS and Proxmox logs nightly, ships to snorlax. See ADR-005.
module "logs" {
  source          = "../modules/proxmox-vm"
  name            = "logs"
  node_name       = "articuno"
  host            = 4
  cores           = 1
  memory_mb       = 1024
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}

output "ip" {
  value = module.logs.ip
}
