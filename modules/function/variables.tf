variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the function app."
}

variable "environment" {
  type        = string
  description = "Environment name (dev / prod)."
}

variable "virtual_network_id" {
  type        = string
  description = "VNet ID for private DNS zone link."
}

variable "private_endpoints_subnet_id" {
  type        = string
  description = "Subnet ID where the function private endpoint NIC will be placed."
}

variable "func_outbound_subnet_id" {
  type        = string
  description = "Delegated subnet ID for function outbound VNet integration."
}

variable "func_storage_account_name" {
  type        = string
  description = "Storage account name used for AzureWebJobsStorage (function host state)."
}

variable "func_package_storage_id" {
  type        = string
  description = "Resource ID of the storage account where function packages are stored."
}

variable "package_url" {
  type        = string
  description = "HTTPS URL to the function zip package in the private storage account. Set to '1' initially; updated by deployment scripts."
  default     = "1"
}
