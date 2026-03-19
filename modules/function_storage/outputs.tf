output "storage_account_id" {
  description = "Resource ID of the function package storage account."
  value       = azurerm_storage_account.func_packages.id
}

output "storage_account_name" {
  description = "Name of the function package storage account."
  value       = azurerm_storage_account.func_packages.name
}

output "container_name" {
  description = "Name of the blob container for function packages."
  value       = azurerm_storage_container.func_packages.name
}
