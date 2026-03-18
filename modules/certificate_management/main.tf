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

# ─── TLS: Self-signed CA (mTLS Root) ──────────────────────────────────────────

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "checkout-assessment-ca-${var.environment}"
    organization = "Checkout Assessment"
  }

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# ─── TLS: Client cert (mTLS) signed by CA ─────────────────────────────────────

resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "checkout-assessment-client-${var.environment}"
    organization = "Checkout Assessment"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "client_auth",
    "digital_signature",
  ]
}

# ─── TLS: Server cert (AGW Listener) signed by CA ─────────────────────────────

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "checkout-assessment-server-${var.environment}"
    organization = "Checkout Assessment"
  }

  # SANs are often needed for server certs
  dns_names = [
    "checkout-${var.environment}.local",
    "localhost"
  ]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "server_auth",
    "digital_signature",
    "key_encipherment",
  ]
}

# ─── Key Vault: Store certs ───────────────────────────────────────────────────

resource "azurerm_key_vault_secret" "ca_cert_pem" {
  name         = "appgw-ca-cert-pem"
  value        = tls_self_signed_cert.ca.cert_pem
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "client_cert_pem" {
  name         = "appgw-client-cert-pem"
  value        = tls_locally_signed_cert.client.cert_pem
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "client_key_pem" {
  name         = "appgw-client-key-pem"
  value        = tls_private_key.client.private_key_pem
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "server_cert_pem" {
  name         = "appgw-server-cert-pem"
  value        = tls_locally_signed_cert.server.cert_pem
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "server_key_pem" {
  name         = "appgw-server-key-pem"
  value        = tls_private_key.server.private_key_pem
  key_vault_id = var.key_vault_id
}
