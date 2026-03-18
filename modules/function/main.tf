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

  app_settings = {
    # Deploy from a zip package stored in the private storage account
    WEBSITE_RUN_FROM_PACKAGE = var.package_url

    # Disable built-in storage for function runtime state (use managed identity)
    WEBSITE_CONTENTOVERVNET              = "1"
    WEBSITE_SKIP_CONTENTSHARE_VALIDATION = "1"

    FUNCTIONS_WORKER_RUNTIME         = "python"
    AzureWebJobsStorage__accountName = var.func_storage_account_name
    AzureWebJobsStorage__credential  = "managedidentity"

    # Application Insights
    APPLICATIONINSIGHTS_CONNECTION_STRING      = var.app_insights_connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
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

# ─── RBAC: grant Function App managed identity access to read packages ────────

resource "azurerm_role_assignment" "func_blob_reader" {
  scope                = var.func_package_storage_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_linux_function_app.func.identity[0].principal_id
}
