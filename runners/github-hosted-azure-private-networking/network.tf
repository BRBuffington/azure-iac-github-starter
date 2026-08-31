data "azurerm_resource_group" "runner" {
  name = var.resource_group_name
}

resource "azurerm_resource_provider_registration" "github_network" {
  name = "GitHub.Network"
}

module "runner_nsg" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.1 release returned by the Terraform Registry.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = var.location
  name                = local.names.runner_nsg
  resource_group_name = data.azurerm_resource_group.runner.name
  security_rules      = local.runner_nsg_rules
  tags                = local.common_tags
}

module "dependency_nsg" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.5.1 release returned by the Terraform Registry.
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = var.location
  name                = local.names.dependency_nsg
  resource_group_name = data.azurerm_resource_group.runner.name
  security_rules      = local.dependency_nsg_rules
  tags                = local.common_tags
}

module "runner_vnet" {
  # checkov:skip=CKV_TF_1:Official AVM Registry module pinned to the exact 0.22.2 release returned by the Terraform Registry.
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  address_space    = [var.vnet_address_space]
  dns_servers      = length(var.dns_servers) == 0 ? null : { dns_servers = var.dns_servers }
  enable_telemetry = var.enable_telemetry
  location         = var.location
  name             = local.names.vnet
  parent_id        = data.azurerm_resource_group.runner.id
  subnets          = local.subnets
  tags             = local.common_tags
}

resource "azapi_resource" "github_network_settings" {
  type      = "GitHub.Network/networkSettings@2024-04-02"
  name      = local.names.network_settings
  parent_id = data.azurerm_resource_group.runner.id
  location  = var.location

  body = {
    properties = {
      businessId = var.github_organization_database_id
      subnetId   = module.runner_vnet.subnets["runners"].resource_id
    }
  }

  response_export_values = {
    github_network_settings_id = "tags.GitHubId"
  }
  schema_validation_enabled = false
  tags                      = local.common_tags

  depends_on = [azurerm_resource_provider_registration.github_network]

  lifecycle {
    ignore_changes = [tags["GitHubId"]]
  }
}
