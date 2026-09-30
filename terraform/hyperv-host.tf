locals {
  numa_node0_vcpu_count = length(var.host_numa_node0_cpus)
  numa_node1_vcpu_count = length(var.host_numa_node1_cpus)
  vcpu_count            = local.numa_node0_vcpu_count + local.numa_node1_vcpu_count
  data_disk_size_bytes  = var.data_disk_size_gib * 1024 * 1024 * 1024
  numa_cell_memory_kib  = (var.memory_mb / 2) * 1024
  vcpu_pins_xml = join("\n", concat(
    [for guest_cpu, host_cpu in var.host_numa_node0_cpus : format("      <vcpupin vcpu=\"%d\" cpuset=\"%d\"/>", guest_cpu, host_cpu)],
    [for guest_cpu, host_cpu in var.host_numa_node1_cpus : format("      <vcpupin vcpu=\"%d\" cpuset=\"%d\"/>", guest_cpu + local.numa_node0_vcpu_count, host_cpu)]
  ))
}

provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_pool" "lab" {
  name = "ad-hyperv-lab"
  type = "dir"

  # Keep runtime disks under libvirt's standard image tree. AppArmor/sVirt
  # commonly blocks qemu from opening disks stored under a user's home dir.
  target {
    path = var.pool_path
  }
}

resource "libvirt_volume" "hyperv1_disk" {
  name   = "${var.vm_name}.qcow2"
  pool   = libvirt_pool.lab.name
  source = startswith(var.base_image_path, "/") ? var.base_image_path : abspath("${path.module}/${var.base_image_path}")
  format = "qcow2"
}

resource "libvirt_volume" "hyperv1_data_disk" {
  name   = "${var.vm_name}-data.raw"
  pool   = libvirt_pool.lab.name
  format = "raw"
  size   = local.data_disk_size_bytes

  xml {
    xslt = templatefile("${path.module}/preallocate-volume.xsl.tftpl", { allocation_bytes = local.data_disk_size_bytes })
  }
}

resource "libvirt_domain" "hyperv1" {
  name   = var.vm_name
  memory = var.memory_mb
  vcpu   = local.vcpu_count

  machine    = "pc"
  qemu_agent = true

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.hyperv1_disk.id
  }
  disk {
    volume_id = libvirt_volume.hyperv1_data_disk.id
  }


  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  # Windows may need several minutes on its first boot with the larger CPU,
  # memory, NUMA, and device configuration.
  timeouts {
    create = "15m"
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "127.0.0.1"
  }

  # Apply virtio devices, two-cell NUMA topology, host CPU pinning, and
  # Windows/KVM paravirtualization features after virtio-win is baked in.
  xml {
    xslt = templatefile("${path.module}/windows-device-models.xsl", {
      vcpu_pins_xml        = local.vcpu_pins_xml
      numa0_guest_last     = local.numa_node0_vcpu_count - 1
      numa1_guest_first    = local.numa_node0_vcpu_count
      numa1_guest_last     = local.vcpu_count - 1
      vcpu_per_numa_node   = local.numa_node0_vcpu_count
      numa_cell_memory_kib = local.numa_cell_memory_kib
    })
  }

  lifecycle {
    precondition {
      condition     = local.numa_node0_vcpu_count > 0 && local.numa_node0_vcpu_count == local.numa_node1_vcpu_count
      error_message = "The two host NUMA CPU lists must be nonempty and contain the same number of CPUs."
    }

    precondition {
      condition     = length(distinct(concat(var.host_numa_node0_cpus, var.host_numa_node1_cpus))) == local.vcpu_count
      error_message = "Each pinned host CPU may appear only once."
    }
  }
}
