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

variable "postgres_k3s_password" {
  type        = string
  sensitive   = true
  description = "Password for k3s user."
}

variable "postgres_admin_password" {
  type        = string
  sensitive   = true
  description = "Password for admin user."
}

variable "postgres_vaultwarden_password" {
  type        = string
  sensitive   = true
  description = "Password for vaultwarden user."
}

variable "postgres_keycloak_password" {
  type        = string
  sensitive   = true
  description = "Password for keycloak user."
}

variable "prometheus_federation_password" {
  type        = string
  sensitive   = true
  description = "Password for Prometheus federation basic HTTP auth."
}
