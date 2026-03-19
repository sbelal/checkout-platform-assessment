"""Test App Gateway → Function mTLS connectivity with client certificate."""
import requests
import subprocess
import json
import os
import sys
import tempfile
import urllib3

# Suppress InsecureRequestWarning (self-signed server cert)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

RG = "rg-checkout-assessment-dev"
FUNC_APP = "func-checkout-dev-001"
KV = "kv-checkout-dev-a1b2"
PIP_NAME = "pip-appgw-checkout-dev"


def az(cmd: str) -> str:
    result = subprocess.run(f"az {cmd}", capture_output=True, text=True, shell=True)
    return result.stdout.strip()


def main():
    print("\n=== App Gateway mTLS POST Test ===\n")

    # Get public IP and function key
    pip = az(f"network public-ip show --name {PIP_NAME} --resource-group {RG} --query ipAddress -o tsv")
    func_key = az(f"functionapp keys list --name {FUNC_APP} --resource-group {RG} --query \"functionKeys.default\" -o tsv")
    print(f"Public IP: {pip}")
    print(f"Function key: {func_key[:10]}...")

    # Load client cert/key — try pre-exported temp files first (KV public access is disabled)
    cert_file = os.path.join(tempfile.gettempdir(), "client-cert.pem")
    key_file = os.path.join(tempfile.gettempdir(), "client-key.pem")

    if os.path.exists(cert_file) and os.path.exists(key_file) and os.path.getsize(cert_file) > 100:
        print(f"Using pre-exported certs from {cert_file}")
    else:
        # Try Key Vault (only works if public access is enabled or via VPN/private endpoint)
        print("Downloading certs from Key Vault...")
        cert_pem = az(f'keyvault secret show --vault-name {KV} --name appgw-client-cert-pem --query value -o tsv')
        key_pem = az(f'keyvault secret show --vault-name {KV} --name appgw-client-key-pem --query value -o tsv')
        if not cert_pem or not key_pem or "ERROR" in cert_pem:
            print("ERROR: Cannot fetch certs from Key Vault (public access disabled).")
            print("  Export certs first from Terraform state:")
            print("    cd environments/dev")
            print('    $state = terraform state pull | ConvertFrom-Json')
            print("    # Extract client cert/key from state resources and write to temp files")
            sys.exit(1)
        with open(cert_file, "w") as f:
            f.write(cert_pem)
        with open(key_file, "w") as f:
            f.write(key_pem)
        print("Client cert/key downloaded from Key Vault")

    url = f"https://{pip}/api/process?code={func_key}"
    payload = {"message": "Hello from App Gateway mTLS test!"}
    headers = {"Content-Type": "application/json"}

    # Test 1: Without client cert (expect 400)
    print("\n--- Test 1: POST without client cert ---")
    try:
        r = requests.post(url, json=payload, headers=headers, verify=False, timeout=10)
        print(f"HTTP {r.status_code}: {r.text[:200]}")
    except Exception as e:
        print(f"Error: {e}")

    # Test 2: With client cert (expect 200)
    print("\n--- Test 2: POST with client cert ---")
    try:
        r = requests.post(
            url,
            json=payload,
            headers=headers,
            cert=(cert_file, key_file),
            verify=False,
            timeout=15,
        )
        print(f"HTTP {r.status_code}")
        print(f"Response: {r.text}")
    except Exception as e:
        print(f"Error: {e}")


    print("\n=== Test Complete ===")


if __name__ == "__main__":
    main()
