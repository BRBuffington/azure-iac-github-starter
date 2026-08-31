mock_provider "azapi" {}
mock_provider "azurerm" {}
mock_provider "github" {}

override_data {
  target = data.azurerm_resource_group.runner
  values = {
    id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example-eus-prd"
    location = "eastus"
    name     = "rg-example-eus-prd"
  }
}

variables {
  subscription_id         = "00000000-0000-0000-0000-000000000000"
  resource_group_name     = "rg-example-eus-prd"
  location                = "eastus"
  scope                   = "example"
  region_alias            = "eus"
  environment             = "prd"
  vnet_address_space      = "10.40.0.0/22"
  runner_subnet_cidr      = "10.40.0.0/24"
  dependency_subnet_cidr  = "10.40.1.0/24"
  route_table_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-connectivity-eus-prd/providers/Microsoft.Network/routeTables/rt-runners-eus-prd"
  approved_private_dependencies = {
    terraform_state_blob = {
      destination_address_prefixes = ["10.40.1.4/32"]
      destination_port_ranges      = ["443"]
    }
    container_registry = {
      destination_address_prefixes = ["10.40.1.5/32", "10.40.1.6/32"]
      destination_port_ranges      = ["443"]
    }
  }
  github_organization             = "example-org"
  github_organization_database_id = "12345678"
  selected_repository_ids         = [123456789]
  selected_workflows              = ["example-org/example-repo/.github/workflows/terraform-cd.yml@main"]
  runner_image_id                 = "2306"
  maximum_runners                 = 10
  deployed_by_repo                = "example-org/azure-platform"
}

run "valid_private_runner_configuration" {
  command = plan

  assert {
    condition     = local.subnets.runners.delegations[0].service_delegation.name == "GitHub.Network/networkSettings"
    error_message = "The runner subnet must be delegated to GitHub.Network/networkSettings."
  }

  assert {
    condition     = local.subnets.runners.default_outbound_access_enabled == false && local.subnets.dependencies.default_outbound_access_enabled == false
    error_message = "Both subnets must disable Azure default outbound access."
  }

  assert {
    condition     = local.runner_nsg_rules.deny_all_inbound.access == "Deny" && local.dependency_nsg_rules.deny_all_inbound.access == "Deny" && local.dependency_nsg_rules.deny_all_inbound.priority == 4096
    error_message = "Both NSGs must carry an explicit deny-all inbound rule, after any named dependency allows."
  }

  assert {
    condition     = local.dependency_nsg_rules.terraform_state_blob.source_address_prefix == "10.40.0.0/24" && local.dependency_nsg_rules.terraform_state_blob.destination_address_prefixes == toset(["10.40.1.4/32"])
    error_message = "Approved private dependencies must allow only the runner subnet to the declared endpoint prefixes."
  }

  assert {
    condition     = azapi_resource.github_network_settings.type == "GitHub.Network/networkSettings@2024-04-02"
    error_message = "The Azure NetworkSettings resource must use the documented stable API version."
  }

  assert {
    condition     = azapi_resource.github_network_settings.body.properties.businessId == "12345678"
    error_message = "The NetworkSettings businessId must use the organization database ID."
  }

  assert {
    condition     = github_actions_runner_group.this.visibility == "selected" && github_actions_runner_group.this.restricted_to_workflows && !github_actions_runner_group.this.allows_public_repositories
    error_message = "The runner group must be restricted to selected repositories and workflows, with public repositories denied."
  }

  assert {
    condition     = github_actions_hosted_runner.this.public_ip_enabled == false
    error_message = "The hosted runner must not receive a static public IP."
  }

  assert {
    condition     = local.runner_subnet_usable_addresses >= local.required_runner_addresses
    error_message = "The valid fixture must satisfy GitHub's 30 percent capacity buffer."
  }
}

run "reject_insufficient_runner_subnet" {
  command = plan

  variables {
    runner_subnet_cidr = "10.40.0.0/29"
    maximum_runners    = 10
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_overlapping_runner_and_dependency_subnets" {
  command = plan

  variables {
    dependency_subnet_cidr = "10.40.0.128/25"
  }

  expect_failures = [terraform_data.configuration_guard]
}

run "reject_version_on_noncustom_image" {
  command = plan

  variables {
    runner_image_version = "2026.08.1"
  }

  expect_failures = [terraform_data.configuration_guard]
}
