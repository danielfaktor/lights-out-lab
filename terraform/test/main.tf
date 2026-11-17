# Throwaway stack: proves apply → reachable VM → destroy. Run: source ../env.sh && terraform apply
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.122"
    }
  }
}

provider "proxmox" {
  # endpoint and token come from env.sh.
  # shortcut: the VIP's cert is signed by the PVE cluster CA and lacks the VIP's IP; give the nodes an ACME cert for a VIP DNS name to drop this.
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
