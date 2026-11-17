output "ip" {
  value = local.ip
}

output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}
