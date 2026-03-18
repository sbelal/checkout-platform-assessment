output "key_vault_uri" {
  description = "URI of the Key Vault."
  value       = module.key_vault.key_vault_uri
}

output "key_vault_name" {
  description = "Name of the Key Vault."
  value       = module.key_vault.key_vault_name
}

output "function_app_name" {
  description = "Name of the Function App."
  value       = module.function.function_app_name
}

output "function_app_hostname" {
  description = "Default hostname of the Function App."
  value       = module.function.function_app_hostname
}

output "appgw_private_ip" {
  description = "Private frontend IP of the Application Gateway."
  value       = module.app_gateway.private_ip
}

output "func_package_storage_name" {
  description = "Name of the function package storage account."
  value       = module.function_storage.storage_account_name
}

output "func_package_container_name" {
  description = "Name of the blob container for function packages."
  value       = module.function_storage.container_name
}

output "appgw_ca_cert_pem" {
  description = "Self-signed CA certificate PEM (distribute to API clients for mTLS)."
  value       = module.certificate_management.ca_cert_pem
  sensitive   = true
}

output "appgw_client_cert_pem" {
  description = "Client certificate PEM signed by the CA."
  value       = module.certificate_management.client_cert_pem
  sensitive   = true
}

output "appgw_client_key_pem" {
  description = "Private key for the client certificate."
  value       = module.certificate_management.client_key_pem
  sensitive   = true
}
