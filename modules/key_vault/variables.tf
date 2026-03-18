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

variable "allowed_ips" {
  type        = list(string)
  description = "List of public IP addresses (CIDR /32) allowed through Key Vault network rules. Use for local terraform apply."
  default     = []
}
