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

output "blob_private_ip" {
  description = "Private IP address of the blob endpoint."
  value       = azurerm_private_endpoint.func_packages.private_service_connection[0].private_ip_address
}

output "queue_private_ip" {
  description = "Private IP address of the queue endpoint."
  value       = azurerm_private_endpoint.func_queue.private_service_connection[0].private_ip_address
}

output "table_private_ip" {
  description = "Private IP address of the table endpoint."
  value       = azurerm_private_endpoint.func_table.private_service_connection[0].private_ip_address
}
