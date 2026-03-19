output "vnet_id" {
  description = "The ID of the virtual network."
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "The name of the virtual network."
  value       = azurerm_virtual_network.vnet.name
}

output "subnet_private_endpoints_id" {
  description = "The ID of the private endpoints subnet."
  value       = azurerm_subnet.private_endpoints.id
}

output "subnet_func_outbound_id" {
  description = "The ID of the Function App outbound subnet."
  value       = azurerm_subnet.func_outbound.id
}

output "subnet_appgw_id" {
  description = "The ID of the Application Gateway subnet."
  value       = azurerm_subnet.appgw.id
}
