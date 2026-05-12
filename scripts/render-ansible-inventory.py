#!/usr/bin/env python3
"""Render ansible/inventory.ini from Terraform vm_addresses output.

Run this from the repository root after `terraform -chdir=terraform apply`, or
from the terraform directory after `terraform apply`.
"""

from __future__ import annotations

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


def terraform_output(root: Path) -> list[str]:
    proc = subprocess.run(
        ["terraform", "-chdir=" + str(root / "terraform"), "output", "-json", "vm_addresses"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    data = json.loads(proc.stdout)
    if isinstance(data, dict) and "value" in data:
        data = data["value"]
    if not isinstance(data, list):
        raise SystemExit(f"Unexpected vm_addresses output shape: {data!r}")
    addresses = [str(item) for item in data if str(item).strip()]
    if not addresses:
        raise SystemExit("Terraform output vm_addresses is empty; inspect `virsh domifaddr hyperv1` or libvirt DHCP leases")
    return addresses


def main() -> None:
    root = repo_root()
    ip = terraform_output(root)[0]
    inventory = root / "ansible" / "inventory.ini"
    inventory.write_text(
        "[windows]\n"
        f"hyperv1 ansible_host={ip} ansible_user=Administrator "
        "ansible_password='P@ssw0rd123!' ansible_connection=ssh "
        "ansible_shell_type=powershell "
        "ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'\n",
        encoding="utf-8",
    )
    print(f"Wrote {inventory} for hyperv1 at {ip}")


if __name__ == "__main__":
    main()
