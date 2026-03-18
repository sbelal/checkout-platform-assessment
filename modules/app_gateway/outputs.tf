output "resource_id" {
  description = "Resource ID of the Application Gateway"
  value       = azurerm_application_gateway.appgw.id
}

output "name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.appgw.name
}

output "private_ip" {
  description = "Private Frontend IP address of the Application Gateway"
  value       = azurerm_application_gateway.appgw.frontend_ip_configuration[0].private_ip_address
}

output "user_assigned_identity_id" {
  description = "Resource ID of the App Gateway User Assigned Identity"
  value       = azurerm_user_assigned_identity.appgw.id
}
