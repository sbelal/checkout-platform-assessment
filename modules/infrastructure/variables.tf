variable "location" {
  type        = string
  description = "The location for the resources."
}

variable "environment" {
  type        = string
  description = "The environment name (dev / prod)."
}

variable "vnet_address_space" {
  description = "The address space for the VNet."
  type        = list(string)
  default     = ["10.0.0.0/16"]
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
  description = "CIDR for the Application Gateway subnet."
  default     = "10.0.3.0/24"
}

variable "appgw_private_ip" {
  type        = string
  description = "Static private IP for the App Gateway internal frontend (must be within appgw subnet)."
  default     = "10.0.3.10"
}



variable "function_package_url" {
  type        = string
  description = "URL to the function zip package. Set to '1' initially; updated by deployment scripts."
  default     = "1"
}

variable "func_service_plan_sku" {
  description = "The SKU for the Function App Service Plan (e.g., EP1, S1, Y1)"
  type        = string
  default     = "EP1"
}

variable "key_vault_suffix" {
  type        = string
  description = "Short alphanumeric suffix for the Key Vault name (globally unique, stable across deploys)."
}

variable "enable_public_access" {
  type        = bool
  description = "When true, App Gateway uses a public IP (dev). When false, App Gateway is private-only (prod)."
  default     = true
}

variable "key_vault_allowed_ip_ranges" {
  type        = list(string)
  default     = []
  description = "Public IPs (CIDR) allowed through the Key Vault network ACL so the Terraform runner can reach it during plan/apply."
}
