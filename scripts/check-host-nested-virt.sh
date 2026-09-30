#!/usr/bin/env bash
set -euo pipefail

missing=0
check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    printf 'ok: %s -> %s\n' "$1" "$(command -v "$1")"
  else
    printf 'missing: %s\n' "$1"
    missing=1
  fi
}

ansible_playbook=${ANSIBLE_PLAYBOOK:-ansible-playbook}
if [ -x .venv/bin/ansible-playbook ]; then
  ansible_playbook=.venv/bin/ansible-playbook
fi

printf '== Required commands ==\n'
for cmd in packer terraform qemu-system-x86_64 qemu-img virsh numactl; do
  check_cmd "$cmd"
done
check_cmd "$ansible_playbook"

if command -v "$ansible_playbook" >/dev/null 2>&1; then
  ansible_core_version=$("$ansible_playbook" --version | sed -n '1s/.*core \([^]]*\).*/\1/p')
  if [ -n "$ansible_core_version" ] && [ "$(printf '%s\n' 2.18 "$ansible_core_version" | sort -V | head -n 1)" = 2.18 ]; then
    printf 'ok: ansible-core %s meets the project minimum\n' "$ansible_core_version"
  else
    printf 'unsupported: ansible-core %s; this project requires 2.18 or newer\n' "${ansible_core_version:-unknown}"
    missing=1
  fi
fi

printf '\n== KVM device ==\n'
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  printf 'ok: current user has read/write access to /dev/kvm\n'
  ls -l /dev/kvm
elif [ -e /dev/kvm ]; then
  printf 'missing access: current user cannot read and write /dev/kvm; check kvm group membership\n'
  missing=1
else
  printf 'missing: /dev/kvm\n'
  missing=1
fi

printf '\n== Nested virtualization ==\n'
if [ -r /sys/module/kvm_intel/parameters/nested ]; then
  value=$(cat /sys/module/kvm_intel/parameters/nested)
  printf 'kvm_intel nested=%s\n' "$value"
  case "$value" in
    Y|y|1) ;;
    *) printf 'warning: Intel nested virtualization does not appear enabled\n' ;;
  esac
elif [ -r /sys/module/kvm_amd/parameters/nested ]; then
  value=$(cat /sys/module/kvm_amd/parameters/nested)
  printf 'kvm_amd nested=%s\n' "$value"
  case "$value" in
    Y|y|1) ;;
    *) printf 'warning: AMD nested virtualization does not appear enabled\n' ;;
  esac
else
  printf 'warning: no readable kvm_intel/kvm_amd nested parameter found\n'
fi

if [ -r /sys/module/kvm_intel/parameters/enable_shadow_vmcs ]; then
  printf 'kvm_intel shadow_vmcs=%s\n' "$(cat /sys/module/kvm_intel/parameters/enable_shadow_vmcs)"
fi
if [ -r /sys/module/kvm_intel/parameters/enable_apicv ]; then
  printf 'kvm_intel apicv=%s\n' "$(cat /sys/module/kvm_intel/parameters/enable_apicv)"
fi
if [ -r /sys/module/kvm_intel/parameters/ept ]; then
  printf 'kvm_intel ept=%s\n' "$(cat /sys/module/kvm_intel/parameters/ept)"
fi

printf '\n== Host NUMA topology ==\n'
numactl --hardware || missing=1

printf '\n== Libvirt default network ==\n'
if command -v virsh >/dev/null 2>&1; then
  virsh -c qemu:///system net-info default || {
    printf 'warning: libvirt default network is unavailable; Terraform expects network_name="default"\n'
    missing=1
  }
else
  printf 'skipped: virsh not installed\n'
fi

printf '\n== virtio-win media ==\n'
virtio_iso='ISOs/virtio-win.iso'
if [ -f "$virtio_iso" ]; then
  printf 'ok: %s\n' "$virtio_iso"
else
  printf 'missing: %s; download the stable virtio-win ISO before running Packer\n' "$virtio_iso"
  missing=1
fi

printf '\n== Libvirt storage capacity ==\n'
df -h /var/lib/libvirt/images || missing=1

printf '\n== Base image path ==\n'
base='output/windows-server-2025-base/windows-server-2025-base.qcow2'
if [ -f "$base" ]; then
  qemu-img info "$base" || true
else
  printf 'missing: %s; run Packer before Terraform apply\n' "$base"
fi

exit "$missing"
