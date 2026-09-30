#!/usr/bin/env python3
"""Render ansible/inventory.ini from Terraform vm_addresses output.

Run this from the repository root after `terraform -chdir=terraform apply`, or
from the terraform directory after `terraform apply`.
"""

from __future__ import annotations

import ipaddress
import os
import json
import subprocess
from pathlib import Path


def repo_root() -> Path:
    here = Path.cwd().resolve()
    if (here / "terraform").is_dir() and (here / "ansible").is_dir():
        return here
    if here.name == "terraform" and (here.parent / "ansible").is_dir():
        return here.parent
    raise SystemExit("Run from repository root or terraform/ directory")


def terraform_output(root: Path, name: str) -> object:
    proc = subprocess.run(
        ["terraform", "-chdir=" + str(root / "terraform"), "output", "-json", name],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    data = json.loads(proc.stdout)
    if isinstance(data, dict) and "value" in data:
        data = data["value"]
    return data


def terraform_addresses(root: Path) -> list[str]:
    data = terraform_output(root, "vm_addresses")
    if not isinstance(data, list):
        raise SystemExit(f"Unexpected vm_addresses output shape: {data!r}")
    addresses = []
    for item in data:
        try:
            address = ipaddress.ip_address(str(item).strip())
        except ValueError:
            continue
        if (
            isinstance(address, ipaddress.IPv4Address)
            and not address.is_link_local
            and not address.is_loopback
        ):
            addresses.append(str(address))
    if not addresses:
        raise SystemExit("Terraform output vm_addresses is empty; inspect `virsh domifaddr hyperv1` or libvirt DHCP leases")
    return addresses


def main() -> None:
    root = repo_root()
    ip = terraform_addresses(root)[0]
    vm_name = str(terraform_output(root, "vm_name")).strip()
    if not vm_name:
        raise SystemExit("Terraform output vm_name is empty")

    password = os.environ.get("AD_LAB_ADMIN_PASSWORD")
    if not password:
        raise SystemExit("Set AD_LAB_ADMIN_PASSWORD before rendering inventory")

    inventory = root / "ansible" / "inventory.ini"
    inventory.write_text(
        "[windows]\n"
        f"{vm_name} ansible_host={ip} ansible_user=Administrator "
        f"ansible_password={json.dumps(password)} ansible_connection=winrm "
        "ansible_port=5985 ansible_winrm_transport=ntlm "
        "ansible_winrm_message_encryption=always\n",
        encoding="utf-8",
    )
    inventory.chmod(0o600)
    print(f"Wrote {inventory} for {vm_name} at {ip}")


if __name__ == "__main__":
    main()
