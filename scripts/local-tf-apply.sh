#!/usr/bin/env bash
# local-tf-apply.sh
#
# Helper script for running terraform apply locally.
# Temporarily adds your public IP to the network allowlists for:
#   - Terraform state storage account
#   - Key Vault
#   - Function package storage account
#
# Usage:
#   ./scripts/local-tf-apply.sh \
#     --env               dev \
#     --tf-state-sa       stckoassignmenttfs001 \
#     --key-vault         kv-checkout-dev-001 \
#     --func-pkg-sa       stckofuncpkgdev001 \
#     --tf-dir            environments/dev
#
# Your IP is removed automatically, even if terraform apply fails.

set -euo pipefail

TF_STATE_SA=""
KEY_VAULT=""
FUNC_PKG_SA=""
TF_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)          ENV="$2";         shift 2 ;;
    --tf-state-sa)  TF_STATE_SA="$2"; shift 2 ;;
    --key-vault)    KEY_VAULT="$2";   shift 2 ;;
    --func-pkg-sa)  FUNC_PKG_SA="$2"; shift 2 ;;
    --tf-dir)       TF_DIR="$2";      shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$TF_STATE_SA" || -z "$KEY_VAULT" || -z "$FUNC_PKG_SA" || -z "$TF_DIR" ]]; then
  echo "Error: all arguments are required."
  exit 1
fi

# ── Get local public IP ───────────────────────────────────────────────────────
echo "▶ Detecting public IP..."
MY_IP=$(curl -s https://api.ipify.org)
echo "  Your public IP: ${MY_IP}"

# ── Cleanup function — always runs on exit ────────────────────────────────────
cleanup() {
  echo ""
  echo "▶ Removing IP ${MY_IP} from network allowlists..."
  az storage account network-rule remove \
    --account-name "${TF_STATE_SA}" \
    --ip-address "${MY_IP}" 2>/dev/null || true
  az keyvault network-rule remove \
    --name "${KEY_VAULT}" \
    --ip-address "${MY_IP}" 2>/dev/null || true
  az storage account network-rule remove \
    --account-name "${FUNC_PKG_SA}" \
    --ip-address "${MY_IP}" 2>/dev/null || true
  echo "  ✅ IP removed from all allowlists"
}
trap cleanup EXIT

# ── Add IP to allowlists ──────────────────────────────────────────────────────
echo "▶ Adding IP to network allowlists..."
az storage account network-rule add --account-name "${TF_STATE_SA}" --ip-address "${MY_IP}"
az keyvault network-rule add        --name "${KEY_VAULT}"           --ip-address "${MY_IP}" 2>/dev/null || true
az storage account network-rule add --account-name "${FUNC_PKG_SA}" --ip-address "${MY_IP}" 2>/dev/null || true
echo "  ✅ IP added (skipped if resource doesn't exist) — waiting 15s..."
sleep 15

# ── Run terraform apply ───────────────────────────────────────────────────────
echo "▶ Running terraform apply in ${TF_DIR}..."
cd "${TF_DIR}"
terraform apply

echo ""
echo "✅ terraform apply complete"
