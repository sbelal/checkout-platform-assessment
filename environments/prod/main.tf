module "infrastructure" {
  source             = "../../modules/infrastructure"
  environment        = var.environment
  location           = var.location
  vnet_address_space = var.vnet_address_space
}
