# PowerShell Script: Local Terraform Apply
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
    Write-Host "Removing IP $Ip from allowlists (if they exist)..."
    # Temporarily set SilentlyContinue so native command errors don't stop the script
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    az storage account network-rule remove --account-name $TfStateSa --ip-address $Ip 2>$null
    az keyvault network-rule remove        --name $KeyVault           --ip-address $Ip 2>$null
    az storage account network-rule remove --account-name $FuncPkgSa  --ip-address $Ip 2>$null
    $ErrorActionPreference = $oldEap
    Write-Host "Cleanup complete."
}

Write-Host "Detecting public IP..."
try {
    $MyIp = Invoke-RestMethod https://api.ipify.org
} catch {
    Write-Error "Failed to detect public IP. Check your internet connection."
    throw $_
}
Write-Host "Your public IP: $MyIp"

$OriginalLocation = Get-Location

try {
    Write-Host "Adding IP to network allowlists (ignoring errors if resources don't exist yet)..."
    $oldEap = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    az storage account network-rule add --account-name $TfStateSa --ip-address $MyIp 2>$null
    az keyvault network-rule add        --name $KeyVault           --ip-address $MyIp 2>$null
    az storage account network-rule add --account-name $FuncPkgSa  --ip-address $MyIp 2>$null
    $ErrorActionPreference = $oldEap

    Write-Host "Waiting 15s for propagation..."
    Start-Sleep -Seconds 15

    Write-Host "Running terraform apply in $TfDir..."
    Set-Location $TfDir
    terraform apply
    
    Write-Host "terraform apply complete"
}
catch {
    Write-Warning "An error occurred during execution. This was expected if it's the first apply and resources don't exist yet."
    throw $_
}
finally {
    Set-Location $OriginalLocation
    Remove-IpFromAllowlists -Ip $MyIp
}
