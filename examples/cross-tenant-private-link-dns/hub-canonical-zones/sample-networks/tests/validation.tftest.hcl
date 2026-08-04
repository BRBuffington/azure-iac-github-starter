mock_provider "azurerm" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  location        = "eastus"
  name_prefix     = "dnslab"
}

run "inbound_subnet_is_delegated_to_the_resolver" {
  command = plan

  # Without this delegation the resolver cannot bind an inbound endpoint and the
  # enterprise forwarder has no target, which is the whole point of the hub.
  assert {
    condition     = module.hub_virtual_network.subnets["dnsr_inbound"].name == "snet-dnsr-inbound"
    error_message = "The hub must expose a dedicated resolver inbound subnet."
  }
}

run "hub_subnets_are_carved_without_collision" {
  command = plan

  assert {
    condition     = local.hub_inbound_subnet_cidr != local.hub_workload_subnet_cidr
    error_message = "Hub subnets must not overlap."
  }

  # /26 leaves headroom over the /28 Azure requires for an inbound endpoint.
  assert {
    condition     = endswith(local.hub_inbound_subnet_cidr, "/26")
    error_message = "The resolver inbound subnet must stay at least a /28; the default carve is a /26."
  }
}

run "reject_identical_address_spaces" {
  command = plan

  variables {
    hub_address_space   = "10.90.0.0/22"
    spoke_address_space = "10.90.0.0/22"
  }

  expect_failures = [terraform_data.configuration_guard]
}
