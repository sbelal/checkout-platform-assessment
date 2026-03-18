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
