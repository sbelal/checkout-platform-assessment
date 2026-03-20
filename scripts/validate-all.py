"""Validate all Terraform modules and environments (no backend required)."""
import subprocess
import sys
import os

MODULES = [
    "modules/vnet",
    "modules/key_vault",
    "modules/certificate_management",
    "modules/function",
    "modules/function_storage",
    "modules/app_gateway",
    "modules/observability",
    "modules/network_security",
    "modules/infrastructure",
]

ENVIRONMENTS = [
    "environments/dev",
    "environments/prod",
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
failed = []


def run(cmd: str, cwd: str) -> bool:
    result = subprocess.run(cmd, shell=True, cwd=cwd)
    return result.returncode == 0


def validate(path: str, label: str):
    full = os.path.join(ROOT, path)
    print(f"\n\033[33m▶ Validating {label}: {path}\033[0m")

    # Remove cached backend config to avoid state access errors
    tf_dir = os.path.join(full, ".terraform")
    if os.path.isdir(tf_dir):
        import shutil
        shutil.rmtree(tf_dir)

    if not run("terraform init -upgrade -backend=false", full):
        print(f"  \033[31m✗ Init failed\033[0m")
        failed.append(path)
        return

    if not run("terraform validate", full):
        print(f"  \033[31m✗ Validation failed\033[0m")
        failed.append(path)
        return

    print(f"  \033[32m✓ Valid\033[0m")


if __name__ == "__main__":
    # Format first
    print("\033[36mRunning terraform fmt -recursive...\033[0m")
    run("terraform fmt -recursive", ROOT)

    print("\033[36m--- Starting Terraform Validation ---\033[0m")

    for m in MODULES:
        validate(m, "module")

    for e in ENVIRONMENTS:
        validate(e, "environment")

    print()
    if failed:
        print(f"\033[31m✗ {len(failed)} failed: {', '.join(failed)}\033[0m")
        sys.exit(1)
    else:
        print(f"\033[32m✓ All {len(MODULES) + len(ENVIRONMENTS)} configs valid!\033[0m")
