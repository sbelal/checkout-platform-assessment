output "key_vault_id" {
  description = "Resource ID of the Key Vault."
  value       = azurerm_key_vault.kv.id
}

output "key_vault_uri" {
  description = "URI of the Key Vault."
  value       = azurerm_key_vault.kv.vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.kv.name
}

output "private_ip" {
  description = "Private IP address of the Key Vault endpoint."
  value       = azurerm_private_endpoint.kv.private_service_connection[0].private_ip_address
}
