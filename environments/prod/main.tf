resource "azurerm_resource_group" "rg" {
  name     = "rg-checkout-assessment-${var.environment}"
  location = var.location
}

module "vnet" {
  source              = "../../modules/vnet"
  vnet_name           = "vnet-checkout-assessment-${var.environment}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space
}
