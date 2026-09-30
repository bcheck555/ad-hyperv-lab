terraform {
  required_version = ">= 1.5.0"

  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
      # v0.9.x changed to an XML-oriented provider schema; this project uses
      # the classic dmacvicar/libvirt Terraform resource model.
      version = "~> 0.8.0"
    }
  }
}
