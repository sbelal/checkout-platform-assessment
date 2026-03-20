variable "location" {
  type        = string
  description = "The location/region where the network security groups will be created."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group."
}

variable "environment" {
  type        = string
  description = "Environment name (dev / prod)."
}

variable "private_endpoints_subnet_id" {
  type        = string
  description = "Subnet ID for private endpoints."
}

variable "func_outbound_subnet_id" {
  type        = string
  description = "Subnet ID for function outbound."
}

variable "appgw_subnet_id" {
  type        = string
  description = "Subnet ID for App Gateway."
}

variable "subnet_private_endpoints_cidr" {
  type        = string
  description = "CIDR for the private endpoints subnet."
}

variable "subnet_func_outbound_cidr" {
  type        = string
  description = "CIDR for the function outbound subnet."
}

variable "subnet_appgw_cidr" {
  type        = string
  description = "CIDR for the App Gateway subnet."
}

variable "key_vault_private_ip" {
  type        = string
  description = "Specific private IP address of the Key Vault endpoint."
}

variable "function_app_private_ip" {
  type        = string
  description = "Specific private IP address of the Function App endpoint."
}

variable "storage_blob_private_ip" {
  type        = string
  description = "Specific private IP address of the Storage Blob endpoint."
}

variable "storage_queue_private_ip" {
  type        = string
  description = "Specific private IP address of the Storage Queue endpoint."
}

variable "storage_table_private_ip" {
  type        = string
  description = "Specific private IP address of the Storage Table endpoint."
}
