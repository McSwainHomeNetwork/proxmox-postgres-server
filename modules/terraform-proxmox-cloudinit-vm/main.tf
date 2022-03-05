terraform {
  required_providers {
    proxmox = {
      source  = "McSwainHomeNetwork/proxmox"
      version = "2.9.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.1.0"
    }
  }
}

provider "proxmox" {
  pm_api_url      = "${var.proxmox_url}/api2/json"
  pm_tls_insecure = var.proxmox_tls_insecure
}

resource "random_id" "mac_address" {
  count       = length(var.mac_address) > 0 ? 0 : 1
  byte_length = 3
}

locals {
  mac_address = length(var.mac_address) > 0 ? lower(var.mac_address) : join("", ["00005e", lower(random_id.mac_address[0].hex)])
  formatted_mac_addr = join(":", [
    substr(local.mac_address, 0, 2),
    substr(local.mac_address, 2, 2),
    substr(local.mac_address, 4, 2),
    substr(local.mac_address, 6, 2),
    substr(local.mac_address, 8, 2),
    substr(local.mac_address, 10, 2),
  ])
}

resource "local_file" "cloud_init_user_data_file" {
  content  = var.cloud_init
  filename = "${path.module}/cloud-init.yaml"
}

resource "null_resource" "cloud_init_config_files" {
  triggers = {
    refresh_on = var.cloud_init
  }

  connection {
    type     = "ssh"
    user     = var.pve_user
    password = var.pve_password
    host     = var.pve_host
  }

  provisioner "file" {
    source      = local_file.cloud_init_user_data_file.filename
    destination = "/var/lib/vz/snippets/cloud-init.${var.name}.yaml"
  }
}

resource "proxmox_vm_qemu" "cloudinit_vm" {
  name        = var.name
  target_node = var.proxmox_target_node

  os_type = "cloud-init"
  clone   = var.cloudinit_template_name

  onboot = var.start_on_boot
  agent  = var.enable_qemu_agent ? 1 : 0

  memory  = var.memory
  balloon = var.min_memory
  cores   = var.cpu_cores
  ssh_private_key = var.deprovision_key

  cicustom                = "user=local:snippets/cloud-init.${var.name}.yaml"
  cloudinit_cdrom_storage = "local-lvm"

  force_recreate_on_change_of = var.cloud_init

  network {
    model   = var.network_model
    macaddr = local.formatted_mac_addr
    bridge  = var.network_bridge
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      type    = disk.value["type"]
      storage = disk.value["storage"]
      size    = disk.value["size"]
    }
  }

  depends_on = [
    null_resource.cloud_init_config_files,
  ]

  lifecycle {
    ignore_changes = [ipconfig0]
  }

  provisioner "remote-exec" {
    when   = destroy
    inline = [
      "sudo systemctl stop postgresql",
      "sudo systemctl stop grafana-server",
      "sudo systemctl stop prometheus",
      "sudo sync",
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = self.default_ipv4_address
      private_key = self.ssh_private_key
    }
  }
}
