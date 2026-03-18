# validate-all.ps1
# This script initializes (without backend) and validates all Terraform modules and environments.

Write-Host "Running terraform fmt -recursive..."
terraform fmt -recursive

$ErrorActionPreference = "Stop"

$modules = @(
    "modules/vnet",
    "modules/key_vault",
    "modules/certificate_management",
    "modules/function",
    "modules/function_storage",
    "modules/app_gateway",
    "modules/infrastructure"
)

$environments = @(
    "environments/dev",
    "environments/prod"
)

Write-Host "--- Starting Terraform Validation ---" -ForegroundColor Cyan

foreach ($module in $modules) {
    Write-Host "Validating module: $module" -ForegroundColor Yellow
    Push-Location $module
    try {
        terraform init -upgrade -backend=false
        if ($LASTEXITCODE -ne 0) { throw "Init failed for $module" }
        terraform validate
        if ($LASTEXITCODE -ne 0) { throw "Validation failed for $module" }
    } finally {
        Pop-Location
    }
}

foreach ($env in $environments) {
    Write-Host "Validating environment: $env" -ForegroundColor Yellow
    Push-Location $env
    try {
        terraform init -backend=false -reconfigure
        if ($LASTEXITCODE -ne 0) { throw "Init failed for $env" }
        terraform validate
        if ($LASTEXITCODE -ne 0) { throw "Validation failed for $env" }
    } finally {
        Pop-Location
    }
}

Write-Host "--- All modules and environments are valid! ---" -ForegroundColor Green
