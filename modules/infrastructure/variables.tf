variable "location" {
  type        = string
  description = "The location for the resources"
}

variable "environment" {
  type        = string
  description = "The environment name"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "The address space for the VNet"
}
