#!/usr/bin/env python3
"""Create a new agenix secret set; never rotate an existing installation."""
import argparse
import json
from pathlib import Path
import secrets
import shutil
import subprocess
import sys


def command(args, data=None):
    return subprocess.run(args, input=data, stdout=subprocess.PIPE, check=True).stdout


def public_key(path):
    data = Path(path).read_bytes()
    subprocess.run(["ssh-keygen", "-lf", path], check=True, stdout=subprocess.DEVNULL)
    fields = data.decode().strip().split()
    if len(fields) < 2 or fields[0] != "ssh-ed25519":
        raise ValueError(f"{path}: expected one ssh-ed25519 public key")
    return " ".join(fields[:2])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("admin-key", "halo-host-key", "arch-host-key", "halo-network", "output"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    output = Path(args.output).absolute()
    if output.exists():
        parser.error(f"output already exists: {output}; refusing to overwrite secrets")
    if not output.parent.is_dir():
        parser.error("output parent directory must exist")
    admin, halo, arch = (public_key(x) for x in (args.admin_key, args.halo_host_key, args.arch_host_key))
    network = Path(args.halo_network).read_bytes()
    if not network.strip():
        parser.error("halo network file is empty")
    def random():
        return secrets.token_hex(32)
    private_halo = command(["wg", "genkey"])
    private_arch = command(["wg", "genkey"])
    public_halo = command(["wg", "pubkey"], private_halo)
    public_arch = command(["wg", "pubkey"], private_arch)
    env = lambda values: "".join(f"{key}={value}\n" for key, value in values.items()).encode()
    entries = {
        "halo-network.age": (network, [admin, halo]),
        "admin-ssh.age": ((admin + "\n").encode(), [admin, halo]),
        "halo-awg.age": (private_halo, [admin, halo]),
        "archserver-awg.age": (private_arch, [admin, arch]),
        "archserver-awg-public.age": (public_arch, [admin, halo]),
        "halo-awg-public.age": (public_halo, [admin, arch]),
        "nixarchserver-authentik.age": (env({"PG_PASS": random(), "AUTHENTIK_SECRET_KEY": random()}), [admin, arch]),
        "nixarchserver-peertube.age": (env({"POSTGRES_PASSWORD": random(), "PEERTUBE_SECRET": random(), "PEERTUBE_ADMIN_PASSWORD": random()[:40], "OIDC_SECRET": random()}), [admin, arch]),
        "nixarchserver-inbuxa.age": (env({"APP_SECRET": random(), "OAUTH_CLIENT_ID": random()[:40], "OAUTH_CLIENT_SECRET": random() + random()}), [admin, arch]),
    }
    output.mkdir(mode=0o700)  # Exclusive: fail if another process created it.
    try:
        for name, (contents, recipients) in entries.items():
            command(["age", *[part for key in dict.fromkeys(recipients) for part in ("-r", key)], "-o", str(output / name)], contents)
        lines = ["{"]
        for name, (_, recipients) in entries.items():
            keys = " ".join(json.dumps(key) for key in dict.fromkeys(recipients))
            lines.append(f"  {json.dumps(name)}.publicKeys = [ {keys} ];")
        lines.append("}")
        (output / "secrets.nix").write_text("\n".join(lines) + "\n")
    except BaseException:
        shutil.rmtree(output)
        raise
    print(f"Encrypted secrets created in {output}")
    print("For new databases only. Register the generated Inbuxa OAuth client before starting webmail.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"bootstrap-secrets: {error}")
