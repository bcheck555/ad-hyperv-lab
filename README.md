# AD Hyper-V Lab

This repository builds and runs a nested Windows Hyper-V lab VM on Linux/KVM.

## Architecture

The workflow is deliberately split into three layers:

1. **Packer** builds a reusable Windows Server 2025 Desktop Experience base qcow2 image.
   - Performs unattended Windows installation using ISO image index 2, the Standard Desktop Experience image for this Windows Server evaluation ISO.
   - Enables WinRM for Packer build-time provisioning.
   - Installs the signed virtio-win guest tools, storage/network drivers, and QEMU guest agent.
   - Installs and enables OpenSSH Server for troubleshooting.
   - Enables Remote Desktop and opens RDP firewall rules in the base image.
   - Leaves WinRM available for Ansible with NTLM message encryption while disabling Basic and unencrypted WinRM.
   - Does **not** install Hyper-V or set the final lab hostname.
2. **Terraform** launches a libvirt VM/domain named `hyperv1` from a clone of the Packer base image.
   - Uses the `dmacvicar/libvirt` provider.
   - Uses host CPU passthrough so nested virtualization can be exposed to Windows.
   - Pins 20 vCPUs and 128 GiB RAM evenly across the host's two NUMA nodes.
   - Keeps the Windows OS disk on the Packer IDE controller for boot compatibility.
   - Uses virtio for the high-I/O data disk and networking.
   - Creates a preallocated 500 GiB raw data disk for Git repositories and nested VM disks.
   - Outputs the VM addresses, RDP endpoints, and Ansible inventory hint.
3. **Ansible** configures the running Windows guest.
   - Sets the hostname to `hyperv1`.
   - Installs Hyper-V and Hyper-V PowerShell tools.
   - Handles required reboots.
   - Creates `D:\Git` and places Hyper-V VM storage under `E:\Hyper-V`.
   - Creates an internal `LabNAT` Hyper-V switch on `192.168.100.0/24`.
   - Verifies SSH, RDP, and Hyper-V readiness.

## Prerequisites

Required commands/tools:

- `packer`
- `terraform`
- `qemu-system-x86_64`
- `qemu-img`
- `virsh`
- Python 3 with `venv`
- `numactl`
- ansible-core 2.18 or newer and `pywinrm` (installed from `requirements.txt`)
- Ansible collections listed in `requirements.yml`

Install the pinned Ansible controller dependency and Windows collection in the
project virtual environment:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/ansible-galaxy collection install -r requirements.yml
```

The Ansible run needs outbound HTTPS access from the Windows guest to the
Chocolatey community feed, the GitHub API, and OpenTofu release downloads.

Download the stable `virtio-win.iso` from the
[virtio-win project](https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md)
and save it as:

```text
ISOs/virtio-win.iso
```

Packer and Terraform run as a regular user. That user needs access to KVM and
the system libvirt socket. One-time host setup normally looks like:

```bash
sudo usermod -aG kvm,libvirt "$USER"
```

Log out and back in after changing group membership. Confirm access without
`sudo`:

```bash
test -r /dev/kvm && test -w /dev/kvm
virsh -c qemu:///system list --all
```

Nested Hyper-V also requires nested virtualization on the Linux/KVM host. Run:

```bash
bash scripts/check-host-nested-virt.sh
```

The script reports missing tools, `/dev/kvm` availability, nested KVM status, libvirt default network status, and whether the Packer base image exists.

## Build the Windows Server base image

Run Packer from the `packer/` directory so relative paths resolve correctly:

```bash
read -r -s -p "Shared lab password: " AD_LAB_ADMIN_PASSWORD
printf '\n'
export AD_LAB_ADMIN_PASSWORD

cd packer
packer init windows-server-2025-qemu.pkr.hcl
PKR_VAR_admin_password="$AD_LAB_ADMIN_PASSWORD" packer validate windows-server-2025-qemu.pkr.hcl
PKR_VAR_admin_password="$AD_LAB_ADMIN_PASSWORD" packer build -force -on-error=cleanup windows-server-2025-qemu.pkr.hcl
```

Packer receives its required sensitive variable through the child-process
environment; the password is not passed as a command-line argument or written
to a build log.

The QEMU builder starts `qemu-system-x86_64` directly, so its temporary build VM
does not appear in `virsh list`. Use the VNC URL printed by Packer to watch the
installer; for example, QEMU display `127.0.0.1:86` maps to TCP port `5986`.
Libvirt manages the final VM created by Terraform, which appears in
`virsh -c qemu:///system list --all` after `terraform apply`.

For a build running on a remote Linux host, find Packer's current VNC endpoint on
the build host:

```bash
grep -oE 'vnc://127\.0\.0\.1:[0-9]+' ../packer_qemu_build.log | tail -n 1
```

Then create the tunnel from your workstation. Substitute the reported remote port
for `5986` and replace the SSH destination:

```bash
ssh -N -L 5901:127.0.0.1:5986 your-user@your-build-host
```

Keep that SSH command running and connect a VNC client on your workstation:

```bash
vncviewer 127.0.0.1:5901
# Or open vnc://127.0.0.1:5901 in a graphical VNC client.
```

If local port `5901` is occupied, choose another unused local port in both
commands. The tunnel is only available while the SSH command remains connected.

Expected base image artifact:

```text
output/windows-server-2025-base/windows-server-2025-base.qcow2
```

The unattended installer selects `/IMAGE/INDEX` value `2` in `packer/answer_files/Autounattend.xml` so the resulting image includes the Windows desktop shell rather than Server Core.

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
- A cloned IDE OS disk matching the Packer build: `hyperv1.qcow2`
- A preallocated 500 GiB raw virtio data disk: `hyperv1-data.raw`
- A libvirt domain: `hyperv1`
- A two-socket, two-cell guest NUMA topology with ten vCPUs and 64 GiB per cell
- Host CPU and memory pinning aligned to the host's two physical NUMA nodes
- A virtio network interface and QEMU guest-agent integration

The default CPU pin lists match this host's dual-socket Xeon topology. Override `host_numa_node0_cpus` and `host_numa_node1_cpus` if the configuration is used on another host.

Inspect the result:

```bash
terraform output
virsh list --all
virsh dominfo hyperv1
```

The `rdp_endpoints` output reports reachable RDP targets as `IP:3389` values. With the default libvirt NAT network, the host can usually connect directly to that guest IP; access from other machines requires routing to the libvirt network or an explicit port-forward outside this Terraform configuration.

## Render Ansible inventory

After `terraform apply`, generate `ansible/inventory.ini` from the Terraform `vm_addresses` output:

```bash
cd ..
python3 scripts/render-ansible-inventory.py
```

The renderer requires `AD_LAB_ADMIN_PASSWORD` to be set but does not write it to
the inventory. Ansible reads it from the process environment; the generated
inventory is mode `0600` and contains only host and connection details. WinRM
uses NTLM message encryption; Basic authentication and unencrypted WinRM
messages remain disabled.

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

Export the shared lab password in the current shell so Ansible can read it:

```bash
export AD_LAB_ADMIN_PASSWORD
```

Check connectivity:

```bash
.venv/bin/ansible -i ansible/inventory.ini windows -m ansible.windows.win_ping
```

Configure the host:

```bash
.venv/bin/ansible-playbook -i ansible/inventory.ini ansible/hyperv-config.yml
```

The first run may reboot the VM after hostname and Hyper-V role changes. Run it a second time to confirm idempotence:

```bash
.venv/bin/ansible-playbook -i ansible/inventory.ini ansible/hyperv-config.yml
```

The playbook also prepares this VM to act as the ADLabV2 Hyper-V host. It
installs Git, the current stable Packer release, the current stable OpenTofu
release, Docker Desktop, and the Windows OpenSSH Server capability, then checks
their versions and service state. OpenTofu is installed from its official
release archive after SHA-256 verification because the Chocolatey community
feed does not publish a stable OpenTofu package.

> [!WARNING]
> Docker Desktop does not support Windows Server. The playbook attempts the
> installation because ADLabV2 uses Docker Desktop for its initial Linux
> Ansible-container bootstrap, but Docker Desktop installation or startup can
> fail on this Windows Server 2025 host. See the
> [Docker Desktop Windows requirements](https://docs.docker.com/desktop/setup/install/windows-install/).

The data disk is initialized once with GPT and split into:

- `D:` — 64 GiB NTFS with 4 KiB allocation units, mounted at `D:\Git`
- `E:` — remaining space as NTFS with 64 KiB allocation units for Hyper-V VHDX and VM configuration files

Nested VMs can use static addresses from `192.168.100.0/24` with gateway
`192.168.100.1`. Configure an appropriate upstream or lab DNS server separately.
The playbook creates NAT but does not run DHCP or DNS inside the Windows
Hyper-V host.

## Cleanup

Destroy the libvirt VM and generated Terraform-managed resources:

```bash
terraform -chdir=terraform destroy
```


Destroy removes both Terraform-managed disks, including the 500 GiB data disk. Copy any Git repositories or VHDX files elsewhere before destroying the stack.

The Packer base image remains under `output/windows-server-2025-base/` unless you remove it manually.

Force rebuild the base image:

```bash
rm -rf output/windows-server-2025-base
cd packer
PKR_VAR_admin_password="$AD_LAB_ADMIN_PASSWORD" packer build -force -on-error=cleanup windows-server-2025-qemu.pkr.hcl
```

Remove generated local inventory:

```bash
rm -f ansible/inventory.ini ansible/known_hosts
```

## Notes and caveats

- Hyper-V inside a VM depends on nested virtualization being enabled on the KVM host and exposed to the guest.
- Terraform uses host CPU passthrough, strict NUMA memory placement, and host-specific vCPU pinning. Review the CPU lists before moving this configuration to different hardware.
- The 500 GiB raw disk is preallocated. Initial creation can take time, but avoids an outer qcow2 copy-on-write layer beneath nested VHDX files.
- The current host stores libvirt images on rotational storage. Moving the pool to SSD or NVMe will improve nested VM responsiveness more than further virtual device tuning.
- RDP is enabled inside Windows by Packer and re-asserted by Ansible. Terraform only reports the discovered guest endpoint; it does not configure host-side NAT port forwarding for TCP/UDP 3389.
- Set only `AD_LAB_ADMIN_PASSWORD` in the current shell; Packer receives its variable through a temporary child-process environment mapping, and Ansible reads the shared variable directly.
- Clear the shared password after Packer and Ansible work is complete with `unset AD_LAB_ADMIN_PASSWORD`.
- Packer temporarily uses Basic, unencrypted WinRM on its isolated build network, then disables it during final shutdown. Runtime automation uses WinRM with NTLM message encryption.
- `ansible/inventory.ini`, `ansible/known_hosts`, logs, Terraform state/plan files, ISOs, and generated disks are ignored by git.
- Commit `terraform/.terraform.lock.hcl` so all users select the same provider build.
