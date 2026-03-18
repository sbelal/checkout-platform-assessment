#!/usr/bin/env bash
# deploy-function.sh
#
# Builds a versioned function zip package and deploys it to the private
# function package storage account, then updates the Function App setting
# WEBSITE_RUN_FROM_PACKAGE and restarts the runtime.
#
# Usage:
#   ./scripts/deploy-function.sh \
#     --env              dev \
#     --storage-account  stckofuncpkgdev001 \
#     --container        func-packages-dev \
#     --function-app     func-checkout-dev-001 \
#     --resource-group   rg-checkout-assessment-dev
#
# Prerequisites:
#   - az CLI installed and logged in (az login)
#   - Your IP must be in the storage account allowlist (see README)

set -euo pipefail

# ── Parse args ────────────────────────────────────────────────────────────────
ENVIRONMENT=""
STORAGE_ACCOUNT=""
CONTAINER=""
FUNCTION_APP=""
RESOURCE_GROUP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)              ENVIRONMENT="$2";      shift 2 ;;
    --storage-account)  STORAGE_ACCOUNT="$2";  shift 2 ;;
    --container)        CONTAINER="$2";        shift 2 ;;
    --function-app)     FUNCTION_APP="$2";     shift 2 ;;
    --resource-group)   RESOURCE_GROUP="$2";   shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$ENVIRONMENT" || -z "$STORAGE_ACCOUNT" || -z "$CONTAINER" || -z "$FUNCTION_APP" || -z "$RESOURCE_GROUP" ]]; then
  echo "Error: all arguments are required."
  exit 1
fi

# ── Version the package ───────────────────────────────────────────────────────
# Use git tag if available, otherwise use date+short SHA
VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "$(date +%Y%m%d%H%M%S)-local")
PACKAGE_NAME="function-${VERSION}.zip"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../src/function" && pwd)"
TMP_ZIP="/tmp/${PACKAGE_NAME}"

echo "▶ Building package: ${PACKAGE_NAME}"
cd "${SRC_DIR}"
pip install -r requirements.txt --target=".python_packages/lib/site-packages" -q
zip -r "${TMP_ZIP}" . -x "*.pyc" -x "__pycache__/*" -x "local.settings.json" -x ".python_packages/*"
# Re-add python_packages
zip -r "${TMP_ZIP}" .python_packages/
echo "  ✅ Package built: ${TMP_ZIP}"

# ── Upload to blob storage ────────────────────────────────────────────────────
echo "▶ Uploading ${PACKAGE_NAME} to ${STORAGE_ACCOUNT}/${CONTAINER}..."
az storage blob upload \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --name "${PACKAGE_NAME}" \
  --file "${TMP_ZIP}" \
  --auth-mode login \
  --overwrite
echo "  ✅ Upload complete"

# ── Generate a SAS URL with 1-year expiry ─────────────────────────────────────
EXPIRY=$(date -u -d "+1 year" +"%Y-%m-%dT%H:%MZ" 2>/dev/null || date -u -v+1y +"%Y-%m-%dT%H:%MZ")
PACKAGE_URL=$(az storage blob generate-sas \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --name "${PACKAGE_NAME}" \
  --permissions r \
  --expiry "${EXPIRY}" \
  --auth-mode login \
  --as-user \
  --full-uri \
  --output tsv)

echo "  ✅ SAS URL generated"

# ── Update WEBSITE_RUN_FROM_PACKAGE and restart ───────────────────────────────
echo "▶ Updating Function App setting WEBSITE_RUN_FROM_PACKAGE..."
az functionapp config appsettings set \
  --name "${FUNCTION_APP}" \
  --resource-group "${RESOURCE_GROUP}" \
  --settings "WEBSITE_RUN_FROM_PACKAGE=${PACKAGE_URL}" \
  --output none

echo "▶ Restarting Function App runtime..."
az functionapp restart \
  --name "${FUNCTION_APP}" \
  --resource-group "${RESOURCE_GROUP}"

echo ""
echo "✅ Deployment complete!"
echo "   Package : ${PACKAGE_NAME}"
echo "   Function: ${FUNCTION_APP}"

# Clean up
rm -f "${TMP_ZIP}"
