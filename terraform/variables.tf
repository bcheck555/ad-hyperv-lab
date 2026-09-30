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
  default     = 131072

  validation {
    condition     = var.memory_mb >= 32768 && var.memory_mb % 2 == 0
    error_message = "memory_mb must be an even value of at least 32768 MiB so it can be split evenly across two NUMA cells."
  }
}

variable "host_numa_node0_cpus" {
  description = "Host CPUs on NUMA node 0 assigned to guest NUMA cell 0."
  type        = list(number)
  default     = [0, 2, 4, 6, 8, 10, 12, 14, 16, 18]
}

variable "host_numa_node1_cpus" {
  description = "Host CPUs on NUMA node 1 assigned to guest NUMA cell 1."
  type        = list(number)
  default     = [1, 3, 5, 7, 9, 11, 13, 15, 17, 19]
}

variable "data_disk_size_gib" {
  description = "Size of the raw Hyper-V data disk in GiB."
  type        = number
  default     = 500

  validation {
    condition     = var.data_disk_size_gib >= 100
    error_message = "data_disk_size_gib must be at least 100 GiB."
  }
}

variable "pool_path" {
  description = "Directory-backed libvirt storage pool used for VM disks."
  type        = string
  default     = "/var/lib/libvirt/images/ad-hyperv-lab"
}
