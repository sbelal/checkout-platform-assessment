variable "location" {
  type        = string
  description = "The location for the resources"
  default     = "uksouth"
}

variable "environment" {
  type        = string
  description = "The environment name"
  default     = "prod"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "The address space for the VNet"
  default     = ["10.1.0.0/16"]
}
