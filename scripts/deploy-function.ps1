<#
.SYNOPSIS
    Builds a versioned function zip package and deploys it to the private
    function package storage account.

.DESCRIPTION
    1. Creates a versioned zip of src/function/
    2. Uploads it to the private Azure Blob container
    3. Generates a SAS URL
    4. Updates the Function App setting WEBSITE_RUN_FROM_PACKAGE
    5. Restarts the Function App runtime

.PARAMETER Env
    Environment name (e.g. dev, prod).

.PARAMETER StorageAccount
    Name of the function package storage account.

.PARAMETER Container
    Name of the blob container (e.g. func-packages-dev).

.PARAMETER FunctionApp
    Name of the Azure Function App.

.PARAMETER ResourceGroup
    Name of the resource group.

.EXAMPLE
    .\scripts\deploy-function.ps1 `
        -Env dev `
        -StorageAccount stckofuncpkgdev001 `
        -Container func-packages-dev `
        -FunctionApp func-checkout-dev-001 `
        -ResourceGroup rg-checkout-assessment-dev
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)][string]$Env,
    [Parameter(Mandatory)][string]$StorageAccount,
    [Parameter(Mandatory)][string]$Container,
    [Parameter(Mandatory)][string]$FunctionApp,
    [Parameter(Mandatory)][string]$ResourceGroup
)

$ErrorActionPreference = "Stop"

# ── Version the package ───────────────────────────────────────────────────────
try {
    $gitDesc = git describe --tags --always --dirty 2>$null
    $Version = if ($LASTEXITCODE -eq 0) { $gitDesc } else { (Get-Date -Format "yyyyMMddHHmmss") + "-local" }
} catch {
    $Version = (Get-Date -Format "yyyyMMddHHmmss") + "-local"
}

$PackageName = "function-$Version.zip"
$SrcDir = Join-Path $PSScriptRoot "..\src\function"
$SrcDir = (Resolve-Path $SrcDir).Path
$TmpZip = Join-Path $env:TEMP $PackageName

Write-Host "▶ Building package: $PackageName"
Push-Location $SrcDir
try {
    pip install -r requirements.txt --target ".python_packages\lib\site-packages" -q

    # Remove existing zip if present
    if (Test-Path $TmpZip) { Remove-Item $TmpZip -Force }

    # Compress the function source (excluding local dev files)
    $filesToZip = Get-ChildItem -Recurse | Where-Object {
        $_.FullName -notmatch "\\__pycache__\\" -and
        $_.Name -ne "local.settings.json" -and
        $_.Name -notlike "*.pyc"
    }
    Compress-Archive -Path $SrcDir -DestinationPath $TmpZip -Force
    Write-Host "  ✅ Package built: $TmpZip"
} finally {
    Pop-Location
}

# ── Upload to blob storage ────────────────────────────────────────────────────
Write-Host "▶ Uploading $PackageName to $StorageAccount/$Container..."
az storage blob upload `
    --account-name $StorageAccount `
    --container-name $Container `
    --name $PackageName `
    --file $TmpZip `
    --auth-mode login `
    --overwrite
if ($LASTEXITCODE -ne 0) { throw "Upload failed." }
Write-Host "  ✅ Upload complete"

# ── Generate SAS URL ──────────────────────────────────────────────────────────
$Expiry = (Get-Date).AddYears(1).ToString("yyyy-MM-ddTHH:mmZ")
$PackageUrl = az storage blob generate-sas `
    --account-name $StorageAccount `
    --container-name $Container `
    --name $PackageName `
    --permissions r `
    --expiry $Expiry `
    --auth-mode login `
    --as-user `
    --full-uri `
    --output tsv
if ($LASTEXITCODE -ne 0) { throw "SAS generation failed." }
Write-Host "  ✅ SAS URL generated"

# ── Update function app setting and restart ───────────────────────────────────
Write-Host "▶ Updating WEBSITE_RUN_FROM_PACKAGE app setting..."
az functionapp config appsettings set `
    --name $FunctionApp `
    --resource-group $ResourceGroup `
    --settings "WEBSITE_RUN_FROM_PACKAGE=$PackageUrl" `
    --output none
if ($LASTEXITCODE -ne 0) { throw "Failed to update app settings." }

Write-Host "▶ Restarting Function App runtime..."
az functionapp restart `
    --name $FunctionApp `
    --resource-group $ResourceGroup
if ($LASTEXITCODE -ne 0) { throw "Failed to restart function app." }

Write-Host ""
Write-Host "✅ Deployment complete!"
Write-Host "   Package : $PackageName"
Write-Host "   Function: $FunctionApp"

# Clean up
Remove-Item $TmpZip -Force -ErrorAction SilentlyContinue
