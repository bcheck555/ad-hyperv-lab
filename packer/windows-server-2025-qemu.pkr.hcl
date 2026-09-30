packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4, < 2.0.0"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

variable "iso_path" {
  type    = string
  default = "../ISOs/26100.32230.260111-0550.lt_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
}

variable "virtio_win_iso_path" {
  description = "Path to the virtio-win driver ISO."
  type        = string
  default     = "../ISOs/virtio-win.iso"
}

variable "admin_password" {
  description = "Temporary local Administrator password used during image construction."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12 && !can(regex("[\\r\\n]", var.admin_password))
    error_message = "The admin_password value must contain at least 12 characters and no newlines."
  }
}

locals {
  admin_password_xml = replace(replace(replace(replace(replace(var.admin_password, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;"), "'", "&apos;")
}

source "qemu" "windows_server_2025" {
  iso_url      = var.iso_path
  iso_checksum = "sha256:7b052573ba7894c9924e3e87ba732ccd354d18cb75a883efa9b900ea125bfd51"

  output_directory = "../output/windows-server-2025-base"
  vm_name          = "windows-server-2025-base.qcow2"
  format           = "qcow2"
  disk_size        = "60000M"
  disk_interface   = "ide"

  cpus         = 4
  memory       = 4096
  accelerator  = "kvm"
  cpu_model    = "host"
  machine_type = "pc-i440fx-8.2"
  headless     = true

  net_device = "e1000"

  cd_files = [var.virtio_win_iso_path]
  cd_label = "PACKERDATA"
  cd_content = {
    "Autounattend.xml" = templatefile("answer_files/Autounattend.xml", { admin_password_xml = local.admin_password_xml })
  }

  boot_wait    = "10s"
  boot_command = ["<spacebar>"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "6h"
  winrm_use_ssl  = false
  winrm_insecure = true

  shutdown_command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \"$ErrorActionPreference = 'Stop'; Set-Item -Path WSMan:\\localhost\\Service\\Auth\\Basic -Value 0; Set-Item -Path WSMan:\\localhost\\Service\\AllowUnencrypted -Value 0; Set-Service WinRM -StartupType Automatic; Set-NetFirewallRule -Name 'ADLab-WinRM-HTTP-In' -Enabled True -Profile Any; Enable-NetFirewallRule -DisplayGroup 'Windows Remote Management'; shutdown.exe /s /t 10 /f /d p:4:1 /c 'Packer shutdown'\""
  shutdown_timeout = "30m"
}

build {
  sources = ["source.qemu.windows_server_2025"]

  provisioner "powershell" {
    inline = [
      "Set-ExecutionPolicy Bypass -Scope LocalMachine -Force",
      "$packerMedia = Get-Volume -FileSystemLabel 'PACKERDATA' -ErrorAction Stop",
      "$virtioIsoSource = Join-Path ($packerMedia.DriveLetter + ':\\') '${basename(var.virtio_win_iso_path)}'",
      "$virtioIsoLocal = Join-Path $env:TEMP 'virtio-win.iso'",
      "Copy-Item -LiteralPath $virtioIsoSource -Destination $virtioIsoLocal -Force",
      "$virtioImage = Mount-DiskImage -ImagePath $virtioIsoLocal -PassThru",
      "try {",
      "$virtioVolume = $virtioImage | Get-Volume",
      "$virtioToolsInstaller = Join-Path ($virtioVolume.DriveLetter + ':\\') 'virtio-win-gt-x64.msi'",
      "$qemuGaInstaller = Join-Path ($virtioVolume.DriveLetter + ':\\') 'guest-agent\\qemu-ga-x86_64.msi'",
      "if (-not (Test-Path -LiteralPath $virtioToolsInstaller)) { throw 'virtio-win-gt-x64.msi was not found in virtio-win.iso' }",
      "if (-not (Test-Path -LiteralPath $qemuGaInstaller)) { throw 'guest-agent\\qemu-ga-x86_64.msi was not found in virtio-win.iso' }",
      "$virtioToolsInstall = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', $virtioToolsInstaller, '/qn', '/norestart') -Wait -PassThru; if ($virtioToolsInstall.ExitCode -notin @(0, 3010)) { throw \"virtio-win tools installation failed with exit code $($virtioToolsInstall.ExitCode)\" }",
      "$qemuGaInstall = Start-Process -FilePath msiexec.exe -ArgumentList @('/i', $qemuGaInstaller, '/qn', '/norestart') -Wait -PassThru; if ($qemuGaInstall.ExitCode -notin @(0, 3010)) { throw \"QEMU guest agent installation failed with exit code $($qemuGaInstall.ExitCode)\" }",
      "$qemuGaService = Get-Service -Name 'QEMU-GA' -ErrorAction Stop",
      "$qemuGaService | Set-Service -StartupType Automatic",
      "$qemuGaService | Start-Service",
      "} finally { Dismount-DiskImage -ImagePath $virtioIsoLocal -ErrorAction SilentlyContinue | Out-Null }",
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service sshd -StartupType Automatic",
      "$sshRule = Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue; if ($null -eq $sshRule) { New-NetFirewallRule -Name OpenSSH-Server-In-TCP -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Profile Any -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null } else { Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Enabled True -Profile Any -Direction Inbound -Action Allow | Out-Null; Get-NetFirewallRule -Name OpenSSH-Server-In-TCP | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort 22 }",
      "$winrmRule = Get-NetFirewallRule -Name ADLab-WinRM-HTTP-In -ErrorAction SilentlyContinue; if ($null -eq $winrmRule) { New-NetFirewallRule -Name ADLab-WinRM-HTTP-In -DisplayName 'AD Lab WinRM HTTP (TCP-In)' -Enabled True -Profile Any -Direction Inbound -Protocol TCP -Action Allow -LocalPort 5985 | Out-Null } else { Set-NetFirewallRule -Name ADLab-WinRM-HTTP-In -Enabled True -Profile Any -Direction Inbound -Action Allow | Out-Null; Get-NetFirewallRule -Name ADLab-WinRM-HTTP-In | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort 5985 }",
      "New-Item -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Force | Out-Null",
      "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\OpenSSH' -Name DefaultShell -Value 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe' -PropertyType String -Force | Out-Null",
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name fDenyTSConnections -Value 0",
      "Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server\\WinStations\\RDP-Tcp' -Name UserAuthentication -Value 1",
      "Set-Service TermService -StartupType Automatic",
      "Start-Service TermService",
      "$rdpRules = @(@{Name='RemoteDesktop-UserMode-In-TCP';DisplayName='Remote Desktop - User Mode (TCP-In)';Protocol='TCP';LocalPort='3389'},@{Name='RemoteDesktop-UserMode-In-UDP';DisplayName='Remote Desktop - User Mode (UDP-In)';Protocol='UDP';LocalPort='3389'}); foreach ($desired in $rdpRules) { $rule = Get-NetFirewallRule -Name $desired.Name -ErrorAction SilentlyContinue; if ($null -eq $rule) { New-NetFirewallRule -Name $desired.Name -DisplayName $desired.DisplayName -Enabled True -Profile Any -Direction Inbound -Protocol $desired.Protocol -Action Allow -LocalPort $desired.LocalPort | Out-Null } else { Set-NetFirewallRule -Name $desired.Name -Enabled True -Profile Any -Direction Inbound -Action Allow | Out-Null; Get-NetFirewallRule -Name $desired.Name | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol $desired.Protocol -LocalPort $desired.LocalPort } }; Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue",
      "Write-Host 'Base image WinRM, SSH, and RDP enabled'"
    ]
  }
}
