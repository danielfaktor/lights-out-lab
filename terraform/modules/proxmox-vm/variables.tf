variable "name" {
  type = string
}

variable "node_name" {
  type = string
  validation {
    condition     = contains(["moltres", "zapdos", "articuno"], var.node_name)
    error_message = "node_name must be moltres, zapdos or articuno."
  }
}

variable "host" {
  description = "Last octet in Lab-VMs (VLAN 20). .2–.99 is the fixed range; DHCP owns the rest."
  type        = number
  validation {
    condition     = var.host >= 2 && var.host <= 99 && floor(var.host) == var.host
    error_message = "host must be a whole number from 2 to 99."
  }
}

variable "cores" {
  type    = number
  default = 2
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "disk_gb" {
  type    = number
  default = 20
}

variable "ssh_public_keys" {
  type = list(string)
}
