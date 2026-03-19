"""Build a versioned function zip and deploy it to the private storage account.

Usage:
    python scripts/deploy-function.py                     # defaults to dev
    python scripts/deploy-function.py --env prod ...      # override for prod
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import zipfile
from datetime import datetime, timezone, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_DIR = os.path.join(ROOT, "src", "function")


def az(cmd: str, check: bool = True) -> str:
    r = subprocess.run(f"az {cmd}", capture_output=True, text=True, shell=True)
    if check and r.returncode != 0:
        print(f"  az error: {r.stderr.strip()}")
        raise RuntimeError(f"az {cmd.split()[0]} failed")
    return r.stdout.strip()


def get_public_ip() -> str:
    r = subprocess.run("curl.exe -s https://api.ipify.org", capture_output=True, text=True, shell=True)
    ip = r.stdout.strip()
    if not ip:
        raise RuntimeError("Failed to detect public IP")
    return ip


def enable_storage_access(sa: str, rg: str, ip: str):
    print(f"▶ Temporarily enabling public access on {sa}...")
    az(f"storage account update --name {sa} --resource-group {rg} --public-network-access Enabled --output none", check=False)
    az(f"storage account network-rule add --account-name {sa} --ip-address {ip}", check=False)
    print("  Waiting 15s for propagation...")
    time.sleep(15)


def disable_storage_access(sa: str, rg: str, ip: str):
    print(f"▶ Restoring storage: disabling public access on {sa}...")
    az(f"storage account network-rule remove --account-name {sa} --ip-address {ip}", check=False)
    az(f"storage account update --name {sa} --resource-group {rg} --public-network-access Disabled --output none", check=False)
    print("  ✅ Public access disabled")


def get_version() -> str:
    try:
        r = subprocess.run("git describe --tags --always --dirty", capture_output=True, text=True, shell=True)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except Exception:
        pass
    return datetime.now().strftime("%Y%m%d%H%M%S") + "-local"


def build_package(version: str) -> str:
    pkg_name = f"function-{version}.zip"
    tmp_zip = os.path.join(tempfile.gettempdir(), pkg_name)
    print(f"▶ Building package: {pkg_name}")

    # Install deps
    subprocess.run(
        f"pip install -r requirements.txt --target .python_packages/lib/site-packages -q",
        shell=True, cwd=SRC_DIR,
    )

    # Create zip (exclude local dev files)
    excludes = {"local.settings.json", "__pycache__"}
    with zipfile.ZipFile(tmp_zip, "w", zipfile.ZIP_DEFLATED) as zf:
        for dirpath, dirnames, filenames in os.walk(SRC_DIR):
            dirnames[:] = [d for d in dirnames if d not in excludes]
            for f in filenames:
                if f in excludes or f.endswith(".pyc"):
                    continue
                full = os.path.join(dirpath, f)
                arcname = os.path.relpath(full, SRC_DIR)
                zf.write(full, arcname)

    print(f"  ✅ Package built: {tmp_zip}")
    return tmp_zip


def main():
    p = argparse.ArgumentParser(description="Deploy function to Azure")
    p.add_argument("--env",             default="dev")
    p.add_argument("--storage-account", default="stckofuncpkgdev001")
    p.add_argument("--container",       default="func-packages-dev")
    p.add_argument("--function-app",    default="func-checkout-dev-001")
    p.add_argument("--resource-group",  default="rg-checkout-assessment-dev")
    args = p.parse_args()

    ip = get_public_ip()
    print(f"  Your IP: {ip}")

    version = get_version()
    pkg_name = f"function-{version}.zip"
    tmp_zip = build_package(version)

    # Enable public access, upload, generate SAS, then disable
    enable_storage_access(args.storage_account, args.resource_group, ip)
    try:
        print(f"▶ Uploading {pkg_name} to {args.storage_account}/{args.container}...")
        az(f"storage blob upload --account-name {args.storage_account} "
           f"--container-name {args.container} --name {pkg_name} "
           f"--file {tmp_zip} --auth-mode login --overwrite")
        print("  ✅ Upload complete")

        expiry = (datetime.now(timezone.utc) + timedelta(days=6)).strftime("%Y-%m-%dT%H:%MZ")
        pkg_url = az(f"storage blob generate-sas --account-name {args.storage_account} "
                     f"--container-name {args.container} --name {pkg_name} "
                     f"--permissions r --expiry {expiry} --auth-mode login "
                     f"--as-user --full-uri --output tsv")
        print("  ✅ SAS URL generated")
    finally:
        disable_storage_access(args.storage_account, args.resource_group, ip)

    # Update app setting + restart
    print("▶ Updating WEBSITE_RUN_FROM_PACKAGE app setting...")
    settings_file = os.path.join(tempfile.gettempdir(), "func-appsettings.json")
    with open(settings_file, "w") as f:
        json.dump({"WEBSITE_RUN_FROM_PACKAGE": pkg_url}, f)
    az(f"functionapp config appsettings set --name {args.function_app} "
       f"--resource-group {args.resource_group} --settings @{settings_file} --output none")
    os.remove(settings_file)

    print("▶ Restarting Function App runtime...")
    az(f"functionapp restart --name {args.function_app} --resource-group {args.resource_group}")

    print(f"\n✅ Deployment complete!")
    print(f"   Package : {pkg_name}")
    print(f"   Function: {args.function_app}")

    os.remove(tmp_zip)


if __name__ == "__main__":
    main()
