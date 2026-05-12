output "vm_name" {
  description = "Libvirt domain name."
  value       = libvirt_domain.hyperv1.name
}

output "vm_addresses" {
  description = "IP addresses reported by libvirt DHCP leases for the VM."
  value       = flatten(libvirt_domain.hyperv1.network_interface[*].addresses)
}

output "ansible_inventory_hint" {
  description = "Command to render ansible/inventory.ini after terraform apply."
  value       = "python3 ../scripts/render-ansible-inventory.py"
}
