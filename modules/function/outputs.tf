output "function_app_id" {
  description = "Resource ID of the Function App."
  value       = azurerm_linux_function_app.func.id
}

output "function_app_name" {
  description = "Name of the Function App."
  value       = azurerm_linux_function_app.func.name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App."
  value       = azurerm_linux_function_app.func.default_hostname
}

output "function_principal_id" {
  description = "Object ID of the Function App system-assigned managed identity."
  value       = azurerm_linux_function_app.func.identity[0].principal_id
}
