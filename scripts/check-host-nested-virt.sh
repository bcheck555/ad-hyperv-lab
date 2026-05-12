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

printf '== Required commands ==\n'
for cmd in packer terraform qemu-system-x86_64 qemu-img virsh ansible-playbook; do
  check_cmd "$cmd"
done

printf '\n== KVM device ==\n'
if [ -e /dev/kvm ]; then
  ls -l /dev/kvm
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

printf '\n== Libvirt default network ==\n'
if command -v virsh >/dev/null 2>&1; then
  virsh net-info default || {
    printf 'warning: libvirt default network is unavailable; Terraform expects network_name="default"\n'
    missing=1
  }
else
  printf 'skipped: virsh not installed\n'
fi

printf '\n== Base image path ==\n'
base='output/windows-server-2025-base/windows-server-2025-base.qcow2'
if [ -f "$base" ]; then
  qemu-img info "$base" || true
else
  printf 'missing: %s; run Packer before Terraform apply\n' "$base"
fi

exit "$missing"
