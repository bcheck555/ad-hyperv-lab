packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_path" {
  type    = string
  default = "../ISOs/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "admin_password" {
  type      = string
  default   = "P@ssw0rd123!"
  sensitive = true
}

source "qemu" "windows_server_2025" {
  iso_url      = var.iso_path
  iso_checksum = "none"

  output_directory = "../output/windows-server-2025-base"
  vm_name          = "windows-server-2025-base.qcow2"
  format           = "qcow2"
  disk_size        = "60000M"
  disk_interface   = "ide"

  cpus        = 4
  memory      = 4096
  accelerator = "kvm"
  headless    = true

  net_device = "e1000"
  qemuargs = [
    ["-cpu", "host"],
    ["-machine", "type=pc,accel=kvm"],
    ["-display", "none"]
  ]

  floppy_files = ["answer_files/Autounattend.xml"]

  boot_wait    = "10s"
  boot_command = ["<spacebar>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "6h"
  winrm_use_ssl  = false
  winrm_insecure = true

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer shutdown\""
  shutdown_timeout = "30m"
}

build {
  sources = ["source.qemu.windows_server_2025"]

  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope LocalMachine -Force",
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service sshd -StartupType Automatic",
      "New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue",
      "New-Item -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Force | Out-Null",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Name DefaultShell -Value 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' -PropertyType String -Force | Out-Null",
      "Write-Host 'Base image SSH enabled'"
    ]
  }
}
