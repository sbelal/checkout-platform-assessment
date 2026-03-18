# Storage account for function deployment packages
resource "azurerm_storage_account" "func_packages" {
  name                     = "stckofuncpkg${replace(var.environment, "-", "")}001"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  # Security: disable all public/anonymous access
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false

  # Entra ID becomes the default authentication method
  default_to_oauth_authentication = true

  min_tls_version = "TLS1_2"

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    # Allow dev machine IPs for local package uploads and terraform apply
    ip_rules = var.allowed_ips
  }
}

# Versioned container per environment for function zip packages
resource "azurerm_storage_container" "func_packages" {
  name                  = "func-packages-${var.environment}"
  storage_account_id    = azurerm_storage_account.func_packages.id
  container_access_type = "private"
}


# ─── RBAC: grant Terraform deployer upload access ─────────────────────────────

resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = azurerm_storage_account.func_packages.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.deployer_principal_id
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "func_packages" {
  name                = "pe-stckofuncpkg-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-stckofuncpkg-${var.environment}"
    private_connection_resource_id = azurerm_storage_account.func_packages.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "funcpkg-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.blob.id]
  }
}

# ─── Private DNS Zone ─────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "funcpkg-blob-dns-link-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}
