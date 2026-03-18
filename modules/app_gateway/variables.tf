variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the App Gateway."
}

variable "environment" {
  type        = string
  description = "Environment name (dev / prod)."
}

variable "appgw_subnet_id" {
  type        = string
  description = "Dedicated subnet ID for the Application Gateway."
}

variable "appgw_private_ip" {
  type        = string
  description = "Static private IP address for the App Gateway internal frontend (must be within appgw subnet CIDR)."
}

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the Key Vault used to store mTLS certificates."
}

variable "ssl_certificate_secret_id" {
  description = "Key Vault Secret ID for the SSL certificate (pfx/pem)"
  type        = string
}

variable "ca_cert_secret_id" {
  description = "Key Vault Secret ID for the CA certificate (PEM content)"
  type        = string
}

variable "function_hostname" {
  type        = string
  description = "FQDN of the private Function App (e.g. func-checkout-dev-001.azurewebsites.net)."
}
