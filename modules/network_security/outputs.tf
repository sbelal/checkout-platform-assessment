output "private_endpoints_nsg_id" {
  description = "Resource ID of the private endpoints NSG."
  value       = azurerm_network_security_group.private_endpoints.id
}

output "func_outbound_nsg_id" {
  description = "Resource ID of the function outbound NSG."
  value       = azurerm_network_security_group.func_outbound.id
}

output "appgw_nsg_id" {
  description = "Resource ID of the App Gateway NSG."
  value       = azurerm_network_security_group.appgw.id
}
