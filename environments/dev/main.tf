module "infrastructure" {
  source             = "../../modules/infrastructure"
  environment        = var.environment
  location           = var.location
  vnet_address_space = var.vnet_address_space

  subnet_private_endpoints_cidr = var.subnet_private_endpoints_cidr
  subnet_func_outbound_cidr     = var.subnet_func_outbound_cidr
  subnet_appgw_cidr             = var.subnet_appgw_cidr
  appgw_private_ip              = var.appgw_private_ip

  function_package_url  = var.function_package_url
  func_service_plan_sku = var.func_service_plan_sku
  key_vault_suffix      = var.key_vault_suffix
  enable_public_access  = var.enable_public_access
}
