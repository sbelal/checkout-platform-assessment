variable "location" {
  type        = string
  description = "Azure region."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group for the storage account."
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
  description = "Subnet ID for the storage private endpoint NIC."
}


variable "deployer_principal_id" {
  type        = string
  description = "Object ID of the deployer (CI/CD SP or local user) granted Blob Data Contributor."
}


