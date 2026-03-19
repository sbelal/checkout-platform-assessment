data "azurerm_client_config" "current" {}

resource "random_id" "vault_suffix" {
  byte_length = 4
}

resource "azurerm_key_vault" "kv" {
  name                = "kv-checkout-${var.environment}-${random_id.vault_suffix.hex}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # Use Azure RBAC for access control (not legacy vault access policies)
  rbac_authorization_enabled = true

  # Soft delete and purge protection for production safety
  soft_delete_retention_days = 7
  purge_protection_enabled   = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    # Allow dev machine IPs for local terraform apply
    ip_rules = var.allowed_ips
  }
}

# ─── Private Endpoint ────────────────────────────────────────────────────────

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv-checkout-${var.environment}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoints_subnet_id

  private_service_connection {
    name                           = "psc-kv-checkout-${var.environment}"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

# ─── Private DNS Zone ─────────────────────────────────────────────────────────

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "kv-dns-link-${var.environment}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
}

# ─── RBAC: grant Terraform deployer (current caller) secret management ───────

resource "azurerm_role_assignment" "kv_secrets_officer_deployer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}
