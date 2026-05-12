variable "libvirt_uri" {
  description = "Libvirt connection URI."
  type        = string
  default     = "qemu:///system"
}

variable "vm_name" {
  description = "Name of the Windows Hyper-V host VM/domain."
  type        = string
  default     = "hyperv1"
}

variable "base_image_path" {
  description = "Path to the Packer-built Windows Server base qcow2 image."
  type        = string
  default     = "../output/windows-server-2025-base/windows-server-2025-base.qcow2"
}

variable "memory_mb" {
  description = "Memory assigned to the Windows VM in MiB. Hyper-V nested labs need more than the Packer build."
  type        = number
  default     = 8192
}

variable "vcpu" {
  description = "Virtual CPUs assigned to the Windows VM."
  type        = number
  default     = 4
}

variable "pool_path" {
  description = "Directory-backed libvirt storage pool used for VM disks."
  type        = string
  default     = "../output/libvirt-pool"
}
