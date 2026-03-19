output "ca_cert_pem" {
  description = "PEM content of the CA certificate"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "ca_cert_secret_id" {
  description = "Key Vault Secret ID for the CA cert"
  value       = azurerm_key_vault_secret.ca_cert_pem.id
}

output "client_cert_secret_id" {
  description = "Key Vault Secret ID for the Client cert"
  value       = azurerm_key_vault_secret.client_cert_pem.id
}

output "server_cert_secret_id" {
  description = "Key Vault Secret ID for the Server cert (Listener) - versionless for App Gateway compatibility"
  value       = azurerm_key_vault_certificate.server.versionless_secret_id
}

output "client_cert_pem" {
  description = "PEM content of the client certificate"
  value       = tls_locally_signed_cert.client.cert_pem
  sensitive   = true
}

output "client_key_pem" {
  description = "PEM content of the client private key"
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}
