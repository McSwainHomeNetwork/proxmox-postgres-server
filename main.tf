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

resource "tls_private_key" "deprovision_key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

locals {
  cloud_init = templatefile("${path.module}/cloud-init.yaml.tpl", {
    ssh_authorized_keys            = concat([tls_private_key.deprovision_key.public_key_openssh], var.ssh_authorized_keys)
    postgres_k3s_password          = var.postgres_k3s_password
    postgres_admin_password        = var.postgres_admin_password
    postgres_keycloak_password     = var.postgres_keycloak_password
    postgres_vaultwarden_password  = var.postgres_vaultwarden_password
    prometheus_federation_password = var.prometheus_federation_password
    grafana_secret_key             = var.grafana_secret_key
    grafana_smtp_password          = var.grafana_smtp_password
    postgres_grafana_password      = var.postgres_grafana_password
  })
}

module "proxmox_cloudinit_vm" {
  source = "./modules/terraform-proxmox-cloudinit-vm"

  name = "database"

  cloud_init          = local.cloud_init
  pve_host            = var.pve_host
  pve_password        = var.pve_password
  proxmox_url         = var.proxmox_url
  proxmox_target_node = var.proxmox_target_node
  deprovision_key     = tls_private_key.deprovision_key.private_key_pem

  cloudinit_template_name = "pcie-storage-ubuntu-server-20.04-focal"

  mac_address = "00005e862517"

  cpu_cores = 4
  memory    = 8192

  disks = [
    {
      size    = "8G"
      storage = "local-lvm"
      type    = "virtio"
    }
  ]
}
