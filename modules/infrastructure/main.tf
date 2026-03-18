data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = "rg-checkout-assessment-${var.environment}"
  location = var.location
}

# ─── Networking ───────────────────────────────────────────────────────────────

module "vnet" {
  source              = "../vnet"
  vnet_name           = "vnet-checkout-assessment-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space

  subnet_private_endpoints_cidr = var.subnet_private_endpoints_cidr
  subnet_func_outbound_cidr     = var.subnet_func_outbound_cidr
  subnet_appgw_cidr             = var.subnet_appgw_cidr
}

# ─── Key Vault ────────────────────────────────────────────────────────────────

module "key_vault" {
  source = "../key_vault"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  environment         = var.environment
  virtual_network_id  = module.vnet.vnet_id

  private_endpoints_subnet_id = module.vnet.subnet_private_endpoints_id
  allowed_ips                 = var.allowed_ips
}

# ─── Function Package Storage ─────────────────────────────────────────────────

module "function_storage" {
  source = "../function_storage"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  environment         = var.environment
  virtual_network_id  = module.vnet.vnet_id

  private_endpoints_subnet_id = module.vnet.subnet_private_endpoints_id
  allowed_ips                 = var.allowed_ips

  # Grant the CI/CD SP / local user upload access
  deployer_principal_id = data.azurerm_client_config.current.object_id
}

# ─── Function App ─────────────────────────────────────────────────────────────

module "function" {
  source = "../function"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  environment         = var.environment
  virtual_network_id  = module.vnet.vnet_id

  private_endpoints_subnet_id = module.vnet.subnet_private_endpoints_id
  func_outbound_subnet_id     = module.vnet.subnet_func_outbound_id

  func_storage_account_name = module.function_storage.storage_account_name
  func_package_storage_id   = module.function_storage.storage_account_id
  service_plan_sku          = var.func_service_plan_sku

  # Package URL is managed by deployment scripts after initial infrastructure apply
  package_url = var.function_package_url
}

# ─── Certificate Management ───────────────────────────────────────────────────

module "certificate_management" {
  source = "../certificate_management"

  key_vault_id        = module.key_vault.key_vault_id
  environment         = var.environment
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  depends_on = [module.key_vault]
}

# ─── Application Gateway ──────────────────────────────────────────────────────

module "app_gateway" {
  source = "../app_gateway"

  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  environment         = var.environment
  appgw_subnet_id     = module.vnet.subnet_appgw_id
  appgw_private_ip    = var.appgw_private_ip
  key_vault_id        = module.key_vault.key_vault_id
  function_hostname   = module.function.function_app_hostname

  # Certs provided by certificate_management module
  ssl_certificate_secret_id = module.certificate_management.server_cert_secret_id
  ca_cert_secret_id         = module.certificate_management.ca_cert_secret_id

  depends_on = [module.key_vault, module.certificate_management]
}
