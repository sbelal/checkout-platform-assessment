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

KV_NAME = "kv-checkout-dev-a1b2"
FUNC_PKG_SA = "stckofuncpkgdev001"


def az(cmd: str) -> str:
    r = subprocess.run(f"az {cmd}", capture_output=True, text=True, shell=True)
    return r.stdout.strip()


def get_public_ip() -> str:
    r = subprocess.run("curl.exe -s https://api.ipify.org", capture_output=True, text=True, shell=True)
    ip = r.stdout.strip()
    if not ip:
        raise RuntimeError("Failed to detect public IP")
    return ip


def tf(cmd: str, cwd: str, extra_env: dict | None = None) -> int:
    env = os.environ.copy()
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(f"terraform {cmd}", shell=True, cwd=cwd, env=env)
    return result.returncode


def add_allowlists(sa: str, ip: str):
    print(f"\n🔒 Adding IP {ip} to network allowlists...")
    az(f"storage account network-rule add --account-name {sa} --ip-address {ip}")
    az(f"storage account network-rule add --account-name {FUNC_PKG_SA} --ip-address {ip}")
    # Enable KV public access and add IP rule so Terraform provider can reach it
    az(f"keyvault update --name {KV_NAME} --public-network-access Enabled")
    az(f"keyvault network-rule add --name {KV_NAME} --ip-address {ip}")
    print("Waiting 15s for propagation...")
    time.sleep(15)


def remove_allowlists(sa: str, ip: str):
    print(f"\n🧹 Removing IP {ip} from network allowlists...")
    az(f"storage account network-rule remove --account-name {sa} --ip-address {ip}")
    az(f"storage account network-rule remove --account-name {FUNC_PKG_SA} --ip-address {ip}")
    az(f"keyvault network-rule remove --name {KV_NAME} --ip-address {ip}")
    print("Cleanup complete.")


def main():
    p = argparse.ArgumentParser(description="Local terraform plan/apply with IP allowlisting")
    p.add_argument("--tf-state-sa", default="stckoassignmenttfs001",
                   help="TF state storage account name")
    p.add_argument("--tf-dir", default="environments/dev",
                   help="Path to the Terraform directory (relative to repo root)")
    p.add_argument("--plan-only", action="store_true",
                   help="Run terraform plan only, skip apply")
    args = p.parse_args()

    tf_dir = os.path.join(ROOT, args.tf_dir)
    if not os.path.isdir(tf_dir):
        print(f"ERROR: {tf_dir} does not exist")
        sys.exit(1)

    ip = get_public_ip()
    print(f"Your public IP: {ip}")

    # Pass IP into Terraform so the KV network_acls ip_rules include it —
    # avoids drift between the CLI rule and TF state.
    tf_env = {"TF_VAR_key_vault_allowed_ip_ranges": f'["{ip}/32"]'}

    try:
        add_allowlists(args.tf_state_sa, ip)

        print(f"\n📋 Running terraform plan in {args.tf_dir}...")
        rc = tf("plan -out=tfplan-local", cwd=tf_dir, extra_env=tf_env)
        if rc != 0:
            print("❌ terraform plan failed")
            sys.exit(rc)

        if args.plan_only:
            print("✅ Plan complete (--plan-only flag set, skipping apply)")
            return

        print(f"\n🚀 Running terraform apply in {args.tf_dir}...")
        rc = tf("apply tfplan-local", cwd=tf_dir, extra_env=tf_env)
        if rc != 0:
            print("❌ terraform apply failed")
            sys.exit(rc)

        print("✅ terraform apply complete")
    finally:
        remove_allowlists(args.tf_state_sa, ip)


if __name__ == "__main__":
    main()
