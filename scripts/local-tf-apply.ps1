<#
.SYNOPSIS
    Runs terraform apply locally by temporarily allowlisting your public IP
    on the Terraform state storage, Key Vault, and function package storage.

.DESCRIPTION
    1. Detects your current public IP
    2. Adds it to the network allowlists of all private Azure resources
    3. Runs terraform apply in the specified environment directory
    4. Removes the IP from all allowlists (always — even on failure)

.PARAMETER TfStateSa
    Name of the Terraform state storage account.

.PARAMETER KeyVault
    Name of the Key Vault.

.PARAMETER FuncPkgSa
    Name of the function package storage account.

.PARAMETER TfDir
    Path to the Terraform environment directory (e.g. environments/dev).

.EXAMPLE
    .\scripts\local-tf-apply.ps1 `
        -TfStateSa  stckoassignmenttfs001 `
        -KeyVault   kv-checkout-dev-001 `
        -FuncPkgSa  stckofuncpkgdev001 `
        -TfDir      environments/dev
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$TfStateSa,
    [Parameter(Mandatory)][string]$KeyVault,
    [Parameter(Mandatory)][string]$FuncPkgSa,
    [Parameter(Mandatory)][string]$TfDir
)

$ErrorActionPreference = "Stop"

function Remove-IpFromAllowlists {
    param([string]$Ip)
    Write-Host "`n▶ Removing IP $Ip from allowlists..."
    az storage account network-rule remove --account-name $TfStateSa --ip-address $Ip 2>$null
    az keyvault network-rule remove        --name $KeyVault           --ip-address $Ip 2>$null
    az storage account network-rule remove --account-name $FuncPkgSa  --ip-address $Ip 2>$null
    Write-Host "  ✅ IP removed from all allowlists"
}

# ── Get public IP ─────────────────────────────────────────────────────────────
Write-Host "▶ Detecting public IP..."
$MyIp = Invoke-RestMethod https://api.ipify.org
Write-Host "  Your public IP: $MyIp"

try {
    # ── Add to allowlists ─────────────────────────────────────────────────────
    Write-Host "▶ Adding IP to network allowlists..."
    az storage account network-rule add --account-name $TfStateSa --ip-address $MyIp
    az keyvault network-rule add        --name $KeyVault           --ip-address $MyIp 2>$null
    az storage account network-rule add --account-name $FuncPkgSa  --ip-address $MyIp 2>$null

    Write-Host "  ✅ IP added (skipped if resource doesn't exist) — waiting 15s..."
    Start-Sleep -Seconds 15

    # ── Run terraform apply ──────────────────────────────────────────────────
    Write-Host "▶ Running terraform apply in $TfDir..."
    Push-Location $TfDir
    try {
        terraform apply
    } finally {
        Pop-Location
    }

    Write-Host "`n✅ terraform apply complete"
} finally {
    # Always remove the IP — even if apply fails
    Remove-IpFromAllowlists -Ip $MyIp
}
