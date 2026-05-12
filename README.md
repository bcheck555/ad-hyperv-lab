# AD Hyper-V Lab

This repository builds and runs a nested Windows Hyper-V lab VM on Linux/KVM.

## Architecture

The workflow is deliberately split into three layers:

1. **Packer** builds a reusable Windows Server 2025 base qcow2 image.
   - Performs unattended Windows installation.
   - Enables WinRM for Packer build-time provisioning.
   - Installs and enables OpenSSH Server for later automation.
   - Does **not** install Hyper-V or set the final lab hostname.
2. **Terraform** launches a libvirt VM/domain named `hyperv1` from a clone of the Packer base image.
   - Uses the `dmacvicar/libvirt` provider.
   - Uses host CPU passthrough so nested virtualization can be exposed to Windows.
   - Outputs the VM addresses for Ansible inventory generation.
3. **Ansible** configures the running Windows guest.
   - Sets the hostname to `hyperv1`.
   - Installs Hyper-V and Hyper-V PowerShell tools.
   - Handles required reboots.
   - Verifies SSH and Hyper-V readiness.

## Prerequisites

Required commands/tools:

- `packer`
- `terraform`
- `qemu-system-x86_64`
- `qemu-img`
- `virsh`
- `ansible-playbook`
- Ansible collection: `ansible.windows`

Install the Ansible Windows collection if needed:

```bash
ansible-galaxy collection install ansible.windows
```

Nested Hyper-V also requires nested virtualization on the Linux/KVM host. Run:

```bash
bash scripts/check-host-nested-virt.sh
```

The script reports missing tools, `/dev/kvm` availability, nested KVM status, libvirt default network status, and whether the Packer base image exists.

## Build the Windows Server base image

Run Packer from the `packer/` directory so relative paths resolve correctly:

```bash
cd packer
packer init windows-server-2025-qemu.pkr.hcl
packer validate windows-server-2025-qemu.pkr.hcl
PACKER_LOG=1 packer build -force -on-error=cleanup windows-server-2025-qemu.pkr.hcl 2>&1 | tee ../packer_qemu_build.log
```

Expected base image artifact:

```text
output/windows-server-2025-base/windows-server-2025-base.qcow2
```

Validate the image from the repository root:

```bash
cd ..
qemu-img info output/windows-server-2025-base/windows-server-2025-base.qcow2
qemu-img check output/windows-server-2025-base/windows-server-2025-base.qcow2
```

## Launch the VM with Terraform

```bash
cd terraform
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Terraform creates:

- A directory-backed libvirt pool: `ad-hyperv-lab`
- A cloned VM disk: `hyperv1.qcow2`
- A libvirt domain: `hyperv1`
- Runtime device models aligned with Packer install-time devices via `terraform/windows-device-models.xsl`:
  - IDE system disk
  - e1000 NIC

The IDE/e1000 models avoid requiring virtio drivers in the Windows base image. If you later inject virtio storage/network drivers during Packer, remove or update the XML transform accordingly.

Inspect the result:

```bash
terraform output
virsh list --all
virsh dominfo hyperv1
```

## Render Ansible inventory

After `terraform apply`, generate `ansible/inventory.ini` from the Terraform `vm_addresses` output:

```bash
cd ..
python3 scripts/render-ansible-inventory.py
```

If Terraform does not discover a DHCP lease, inspect the VM manually and copy the example inventory:

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
# Edit ansible/inventory.ini and replace REPLACE_WITH_TERRAFORM_OUTPUT_IP
```

Useful fallback commands:

```bash
virsh domifaddr hyperv1
virsh net-dhcp-leases default
```

## Configure Hyper-V with Ansible

Check connectivity:

```bash
ansible -i ansible/inventory.ini windows -m ansible.windows.win_ping
```

Configure the host:

```bash
ansible-playbook -i ansible/inventory.ini ansible/hyperv-config.yml
```

The first run may reboot the VM after hostname and Hyper-V role changes. Run it a second time to confirm idempotence:

```bash
ansible-playbook -i ansible/inventory.ini ansible/hyperv-config.yml
```

## Cleanup

Destroy the libvirt VM and generated Terraform-managed resources:

```bash
terraform -chdir=terraform destroy
```

The Packer base image remains under `output/windows-server-2025-base/` unless you remove it manually.

Force rebuild the base image:

```bash
rm -rf output/windows-server-2025-base
cd packer
packer build -force -on-error=cleanup windows-server-2025-qemu.pkr.hcl
```

Remove generated local inventory:

```bash
rm -f ansible/inventory.ini
```

## Notes and caveats

- Hyper-V inside a VM depends on nested virtualization being enabled on the KVM host and exposed to the guest.
- Terraform uses `cpu { mode = "host-passthrough" }`; validate this against the installed `dmacvicar/libvirt` provider version.
- The default lab password is currently hardcoded as `P@ssw0rd123!` for local lab convenience. Do not reuse it outside isolated lab environments.
- If you override Packer's `admin_password`, update `packer/answer_files/Autounattend.xml` to match; Packer WinRM authentication depends on both values being identical.
- `ansible/inventory.ini`, logs, Terraform state, and generated disks are ignored by git.
