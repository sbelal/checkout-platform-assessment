variable "vnet_name" {
  type        = string
  description = "The name of the virtual network."
}

variable "location" {
  type        = string
  description = "The location/region where the virtual network will be created."
}

variable "resource_group_name" {
  type        = string
  description = "The name of the resource group where the virtual network will be created."
}

variable "address_space" {
  type        = list(string)
  description = "The address space that is used by the virtual network."
}

variable "subnet_private_endpoints_cidr" {
  type        = string
  description = "CIDR for the private endpoints subnet."
  default     = "10.0.1.0/24"
}

variable "subnet_func_outbound_cidr" {
  type        = string
  description = "CIDR for the Function App outbound VNet integration subnet."
  default     = "10.0.2.0/24"
}

variable "subnet_appgw_cidr" {
  type        = string
  description = "CIDR for the Application Gateway subnet (requires minimum /26)."
  default     = "10.0.3.0/24"
}
