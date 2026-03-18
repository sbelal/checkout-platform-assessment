terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# (TLS generation and KV secret logic moved to certificate_management module)

# ─── User-assigned identity for App Gateway to read Key Vault secrets ─────────

resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-appgw-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
}

resource "azurerm_role_assignment" "appgw_kv_secrets_user" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

# ─── App Gateway ──────────────────────────────────────────────────────────────

locals {
  backend_pool_name         = "bp-func-${var.environment}"
  backend_http_setting_name = "bhs-func-${var.environment}"
  frontend_ip_name          = "fip-internal-${var.environment}"
  frontend_port_name        = "fport-443-${var.environment}"
  listener_name             = "listener-https-${var.environment}"
  routing_rule_name         = "rule-func-${var.environment}"
  ssl_profile_name          = "ssl-profile-mtls-${var.environment}"
  trusted_root_cert_name    = "trusted-root-ca-${var.environment}"
}

data "azurerm_key_vault_secret" "ca_cert" {
  name         = element(split("/", var.ca_cert_secret_id), 4)
  key_vault_id = var.key_vault_id
}

resource "azurerm_application_gateway" "appgw" {
  name                = "appgw-checkout-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  waf_configuration {
    enabled          = true
    firewall_mode    = "Prevention"
    rule_set_type    = "OWASP"
    rule_set_version = "3.2"
  }

  gateway_ip_configuration {
    name      = "ipconfig-${var.environment}"
    subnet_id = var.appgw_subnet_id
  }

  # Internal private frontend — not exposed to the internet
  frontend_ip_configuration {
    name                          = local.frontend_ip_name
    subnet_id                     = var.appgw_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.appgw_private_ip
  }

  frontend_port {
    name = local.frontend_port_name
    port = 443
  }

  # mTLS: verify client certificates against the trusted CA
  ssl_profile {
    name = local.ssl_profile_name

    ssl_policy {
      policy_type = "Predefined"
      policy_name = "AppGwSslPolicy20220101"
    }

    trusted_client_certificate_names = [local.trusted_root_cert_name]
  }

  # CA cert used to validate incoming client certificates
  trusted_root_certificate {
    name = local.trusted_root_cert_name
    data = base64encode(data.azurerm_key_vault_secret.ca_cert.value)
  }

  backend_address_pool {
    name  = local.backend_pool_name
    fqdns = [var.function_hostname]
  }

  backend_http_settings {
    name                  = local.backend_http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 443
    protocol              = "Https"
    request_timeout       = 60

    # Trust the function app's privatelink TLS cert
    pick_host_name_from_backend_address = true
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Https"
    ssl_profile_name               = local.ssl_profile_name

    ssl_certificate_name = "appgw-ssl-cert-${var.environment}"
  }

  ssl_certificate {
    name                = "appgw-ssl-cert-${var.environment}"
    key_vault_secret_id = var.ssl_certificate_secret_id
  }

  request_routing_rule {
    name                       = local.routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_pool_name
    backend_http_settings_name = local.backend_http_setting_name
    priority                   = 100
  }
}
