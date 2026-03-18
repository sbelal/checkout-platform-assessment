variable "location" {
  type        = string
  description = "Azure region"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., dev, prod)"
}

variable "function_app_id" {
  type        = string
  description = "ID of the Function App to monitor"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}
