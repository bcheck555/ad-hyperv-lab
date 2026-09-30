output "vm_name" {
  description = "Libvirt domain name."
  value       = libvirt_domain.hyperv1.name
}

output "data_disk" {
  description = "Terraform-managed raw data disk attached to the Hyper-V host."
  value = {
    name     = libvirt_volume.hyperv1_data_disk.name
    size_gib = var.data_disk_size_gib
    format   = libvirt_volume.hyperv1_data_disk.format
  }
}

output "vm_addresses" {
  description = "IP addresses reported by libvirt DHCP leases for the VM."
  value       = flatten(libvirt_domain.hyperv1.network_interface[*].addresses)
}

output "rdp_endpoints" {
  description = "RDP endpoints for the VM addresses discovered from libvirt DHCP leases."
  value       = [for address in flatten(libvirt_domain.hyperv1.network_interface[*].addresses) : "${address}:3389"]
}

output "ansible_inventory_hint" {
  description = "Command to render ansible/inventory.ini after terraform apply."
  value       = "python3 ../scripts/render-ansible-inventory.py"
}
