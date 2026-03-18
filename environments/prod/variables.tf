variable "location" {
  type        = string
  description = "The location for the resources."
  default     = "uksouth"
}

variable "environment" {
  type        = string
  description = "The environment name."
  default     = "prod"
}

variable "vnet_address_space" {
  type        = list(string)
  description = "The address space for the VNet."
  default     = ["10.1.0.0/16"]
}

variable "subnet_private_endpoints_cidr" {
  type        = string
  description = "CIDR for the private endpoints subnet."
  default     = "10.1.1.0/24"
}

variable "subnet_func_outbound_cidr" {
  type        = string
  description = "CIDR for the Function App outbound VNet integration subnet."
  default     = "10.1.2.0/24"
}

variable "subnet_appgw_cidr" {
  type        = string
  description = "CIDR for the Application Gateway subnet."
  default     = "10.1.3.0/24"
}

variable "appgw_private_ip" {
  type        = string
  description = "Static private IP for the App Gateway internal frontend."
  default     = "10.1.3.10"
}

variable "allowed_ips" {
  type        = list(string)
  description = "Public IPs allowed through network rules for local terraform apply. Leave empty for CI/CD."
  default     = []
}

variable "function_package_url" {
  type        = string
  description = "URL to the function zip package. Set to '1' initially; updated by deployment scripts."
  default     = "1"
}
