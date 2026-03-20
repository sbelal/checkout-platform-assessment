# NSG for private endpoints subnet — allow specific inbound sources only
resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-private-endpoints-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                    = "AllowSubnetHttpsInbound"
    priority                = 100
    direction               = "Inbound"
    access                  = "Allow"
    protocol                = "Tcp"
    source_port_range       = "*"
    destination_port_range  = "443"
    source_address_prefixes = [var.subnet_appgw_cidr, var.subnet_func_outbound_cidr]
    # Restrict destination to ONLY the private endpoint IPs within the subnet
    destination_address_prefixes = [
      var.key_vault_private_ip,
      var.function_app_private_ip,
      var.storage_blob_private_ip,
      var.storage_queue_private_ip,
      var.storage_table_private_ip
    ]
  }

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = var.private_endpoints_subnet_id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

# NSG for Function App outbound subnet — allow specific egress targets only
resource "azurerm_network_security_group" "func_outbound" {
  name                = "nsg-func-outbound-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                   = "AllowHttpsOutboundToPrivateEndpoints"
    priority               = 100
    direction              = "Outbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "443"
    source_address_prefix  = var.subnet_func_outbound_cidr
    # Restrict destination to specific private endpoint IPs
    destination_address_prefixes = [
      var.key_vault_private_ip,
      var.storage_blob_private_ip,
      var.storage_queue_private_ip,
      var.storage_table_private_ip
    ]
  }

  security_rule {
    name                       = "AllowHttpsOutboundToInternet"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.subnet_func_outbound_cidr
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "DenyAllOutbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "func_outbound" {
  subnet_id                 = var.func_outbound_subnet_id
  network_security_group_id = azurerm_network_security_group.func_outbound.id
}

# NSG for App Gateway subnet — allow public HTTPS + specific backend egress
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-appgw-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  security_rule {
    name                       = "AllowHttpsInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = var.subnet_appgw_cidr
  }

  # Required for App Gateway v2 health probes
  security_rule {
    name                       = "AllowGatewayManagerInbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                   = "AllowOutboundToBackends"
    priority               = 100
    direction              = "Outbound"
    access                 = "Allow"
    protocol               = "Tcp"
    source_port_range      = "*"
    destination_port_range = "443"
    source_address_prefix  = var.subnet_appgw_cidr
    # Restrict destination to ONLY the Function App and Key Vault private IPs
    destination_address_prefixes = [
      var.function_app_private_ip,
      var.key_vault_private_ip
    ]
  }

  security_rule {
    name                       = "DenyAllOutbound"
    priority                   = 4096
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = var.appgw_subnet_id
  network_security_group_id = azurerm_network_security_group.appgw.id
}
