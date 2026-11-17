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

module "test_vm" {
  source          = "../modules/proxmox-vm"
  name            = "tf-test"
  node_name       = "moltres"
  host            = 10
  ssh_public_keys = [trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))]
}

output "ip" {
  value = module.test_vm.ip
}
