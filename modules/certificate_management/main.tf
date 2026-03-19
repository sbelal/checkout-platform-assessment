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

# ─── Key Vault: Store CA and client certs ─────────────────────────────────────

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

# ─── Key Vault: Server cert generated directly (PFX for App Gateway listener) ─


resource "azurerm_key_vault_certificate" "server" {
  name         = "appgw-server-cert"
  key_vault_id = var.key_vault_id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      key_usage = [
        "digitalSignature",
        "keyEncipherment",
      ]

      subject            = "CN=checkout-assessment-server-${var.environment}"
      validity_in_months = 12

      subject_alternative_names {
        dns_names = [
          "checkout-${var.environment}.local",
          "localhost",
        ]
      }

      extended_key_usage = ["1.3.6.1.5.5.7.3.1"] # serverAuth
    }
  }
}
