provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_pool" "lab" {
  name = "ad-hyperv-lab"
  type = "dir"
  path = abspath("${path.module}/${var.pool_path}")
}

resource "libvirt_volume" "hyperv1_disk" {
  name   = "${var.vm_name}.qcow2"
  pool   = libvirt_pool.lab.name
  source = abspath("${path.module}/${var.base_image_path}")
  format = "qcow2"
}

resource "libvirt_domain" "hyperv1" {
  name   = var.vm_name
  memory = var.memory_mb
  vcpu   = var.vcpu

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.hyperv1_disk.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
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

  # Keep runtime devices aligned with the Packer install-time devices.
  # Windows Server was installed on an IDE disk with an e1000 NIC; switching
  # to virtio here requires injecting virtio storage/network drivers first.
  xml {
    xslt = file("${path.module}/windows-device-models.xsl")
  }
}
