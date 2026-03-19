variable "location" {
  type        = string
  description = "Azure region for Key Vault."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for Key Vault."
}

variable "environment" {
  type        = string
  description = "Environment name (dev / prod)."
}

variable "virtual_network_id" {
  type        = string
  description = "VNet ID for the private DNS zone link."
}

variable "private_endpoints_subnet_id" {
  type        = string
  description = "Subnet ID for the Key Vault private endpoint NIC."
}



variable "key_vault_suffix" {
  type        = string
  description = "Short alphanumeric suffix to make the Key Vault name globally unique (stable across deploys)."
}

variable "allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Public IPs (CIDR or single /32) allowed through the Key Vault network ACL. Add your Terraform runner IP here so plan/apply can reach the vault."
}
