output "ip" {
    value = proxmox_vm_qemu.cloudinit_vm.default_ipv4_address
}
