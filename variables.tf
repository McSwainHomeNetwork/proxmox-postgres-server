variable "proxmox_url" {
  type        = string
  sensitive   = true
  description = "The URL for Proxmox. The module will automatically append `/api2/json` for the API"
}

variable "proxmox_target_node" {
  type        = string
  default     = "proxmox"
  description = "The target proxmox node name to deploy to."
}

variable "pve_host" {
  type        = string
  sensitive   = true
  description = "Hostname of SSH session to proxmox to load cloud-init file."
}

variable "pve_password" {
  type        = string
  sensitive   = true
  description = "Password of the user to connect via SSH to proxmox to load cloud-init file."
}

variable "ssh_authorized_keys" {
  type        = list(string)
  sensitive   = true
  description = "List of authorized keys for SSHing into the instance."
}
