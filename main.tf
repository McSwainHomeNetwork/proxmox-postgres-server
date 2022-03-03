terraform {
  backend "s3" {
    bucket                      = "terraform-states-mcswainhomenetwork"
    key                         = "terraform-proxmox-postgres-server.tfstate"
    region                      = "us-east-1"
    endpoint                    = "http://192.168.1.135:9000"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
  required_providers {
    proxmox = {
      source  = "McSwainHomeNetwork/proxmox"
      version = "2.9.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.1.0"
    }
  }
}

locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_authorized_keys           = var.ssh_authorized_keys
    postgres_k3s_password         = var.postgres_k3s_password
    postgres_admin_password       = var.postgres_admin_password
    postgres_keycloak_password    = var.postgres_keycloak_password
    postgres_vaultwarden_password = var.postgres_vaultwarden_password
  })
}

module "proxmox_cloudinit_vm" {
  source  = "app.terraform.io/McSwainHomeNetwork/cloudinit-vm/proxmox"
  version = "0.0.1"

  name = "postgres"

  cloud_init          = local.cloud_init
  pve_host            = var.pve_host
  pve_password        = var.pve_password
  proxmox_url         = var.proxmox_url
  proxmox_target_node = var.proxmox_target_node

  cloudinit_template_name = "pcie-storage-ubuntu-server-20.04-focal"

  mac_address = "00005e862517"

  cpu_cores = 2
  memory    = 4096

  disks = [
    {
      size    = "8G"
      storage = "local-lvm"
      type    = "virtio"
    }
  ]
}
