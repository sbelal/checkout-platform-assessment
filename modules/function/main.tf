# Elastic Premium plan — required for VNet integration + private endpoints
resource "azurerm_service_plan" "func" {
  name                = "asp-checkout-func-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku
}

# System-assigned managed identity for the function app
resource "azurerm_linux_function_app" "func" {
  name                = "func-checkout-${var.environment}-001"
  resource_group_name = var.resource_group_name
  location            = var.location

  service_plan_id               = azurerm_service_plan.func.id
  storage_account_name          = var.func_storage_account_name
  storage_uses_managed_identity = true

  # Disable all public access — only reachable via private endpoint
  public_network_access_enabled = false
  https_only                    = true

  # Outbound VNet integration — all egress routed through the VNet
  virtual_network_subnet_id = var.func_outbound_subnet_id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    vnet_route_all_enabled = true

    application_stack {
      python_version = "3.11"
    }
  }

  # Disable built-in logging to prevent Azure from injecting the deprecated
  # AzureWebJobsDashboard setting (which requires shared keys — disabled here)
  builtin_logging_enabled = false

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME         = "python"
    AzureWebJobsStorage__accountName = var.func_storage_account_name
    AzureWebJobsStorage__credential  = "managedidentity"

    # Application Insights
    APPLICATIONINSIGHTS_CONNECTION_STRING      = var.app_insights_connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
  }

  # WEBSITE_RUN_FROM_PACKAGE is managed by the deploy script, not Terraform.
  # Prevent terraform apply from resetting it back to the default value.
  lifecycle {
    ignore_changes = [app_settings["WEBSITE_RUN_FROM_PACKAGE"]]
  }
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "func" {
  name                = "pe-func-checkout-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-func-checkout-${var.environment}"
    private_connection_resource_id = azurerm_linux_function_app.func.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "func-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.func.id]
  }
}

# ─── Private DNS Zone ─────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "func" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "func" {
  name                  = "func-dns-link-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.func.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}

# ─── RBAC: grant Function App managed identity full storage access ─────────────
# AzureWebJobsStorage via managed identity requires these roles for
# internal state management (leases, queues, tables) plus package reads.

resource "azurerm_role_assignment" "func_blob_owner" {
  scope                = var.func_package_storage_id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_queue_contributor" {
  scope                = var.func_package_storage_id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}

resource "azurerm_role_assignment" "func_table_contributor" {
  scope                = var.func_package_storage_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}
