"""Local Terraform Apply — temporarily allowlists your IP on the TF state storage.

Usage:
    python scripts/local-tf-apply.py                                          # defaults
    python scripts/local-tf-apply.py --tf-state-sa stckoassignmenttfs001 --tf-dir environments/dev
"""
import argparse
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def az(cmd: str, check: bool = False) -> str:
    r = subprocess.run(f"az {cmd}", capture_output=True, text=True, shell=True)
    return r.stdout.strip()


def get_public_ip() -> str:
    r = subprocess.run("curl.exe -s https://api.ipify.org", capture_output=True, text=True, shell=True)
    ip = r.stdout.strip()
    if not ip:
        raise RuntimeError("Failed to detect public IP")
    return ip


def remove_ip(sa: str, ip: str):
    print(f"Removing IP {ip} from TF state storage allowlist...")
    az(f"storage account network-rule remove --account-name {sa} --ip-address {ip}")
    print("Cleanup complete.")


def main():
    p = argparse.ArgumentParser(description="Local terraform apply with IP allowlisting")
    p.add_argument("--tf-state-sa", default="stckoassignmenttfs001",
                   help="TF state storage account name")
    p.add_argument("--tf-dir", default="environments/dev",
                   help="Path to the Terraform directory (relative to repo root)")
    args = p.parse_args()

    tf_dir = os.path.join(ROOT, args.tf_dir)
    if not os.path.isdir(tf_dir):
        print(f"ERROR: {tf_dir} does not exist")
        sys.exit(1)

    ip = get_public_ip()
    print(f"Your public IP: {ip}")

    try:
        print("Adding IP to TF state storage allowlist...")
        az(f"storage account network-rule add --account-name {args.tf_state_sa} --ip-address {ip}")

        print("Waiting 15s for propagation...")
        time.sleep(15)

        print(f"Running terraform apply in {args.tf_dir}...")
        result = subprocess.run("terraform apply -auto-approve", shell=True, cwd=tf_dir)

        if result.returncode != 0:
            print("terraform apply failed")
            sys.exit(result.returncode)

        print("terraform apply complete")
    finally:
        remove_ip(args.tf_state_sa, ip)


if __name__ == "__main__":
    main()
