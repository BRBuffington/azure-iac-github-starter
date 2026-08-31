resource "github_actions_runner_group" "this" {
  name                       = local.names.runner_group
  visibility                 = "selected"
  selected_repository_ids    = var.selected_repository_ids
  restricted_to_workflows    = true
  selected_workflows         = sort(tolist(var.selected_workflows))
  allows_public_repositories = false
}

resource "terraform_data" "github_network_association" {
  triggers_replace = {
    network_configuration_name = local.names.network_configuration
    network_settings_id        = azapi_resource.github_network_settings.output.github_network_settings_id
    organization               = var.github_organization
    runner_group_id            = github_actions_runner_group.this.id
  }

  provisioner "local-exec" {
    command     = "& '${path.module}/scripts/sync-github-network.ps1'"
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]

    environment = {
      APN_MODE                       = "Ensure"
      APN_NETWORK_CONFIGURATION_NAME = local.names.network_configuration
      APN_NETWORK_SETTINGS_ID        = azapi_resource.github_network_settings.output.github_network_settings_id
      APN_ORGANIZATION               = var.github_organization
      APN_RUNNER_GROUP_ID            = github_actions_runner_group.this.id
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "& '${path.module}/scripts/sync-github-network.ps1'"
    interpreter = ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]

    environment = {
      APN_MODE                       = "Remove"
      APN_NETWORK_CONFIGURATION_NAME = self.triggers_replace.network_configuration_name
      APN_NETWORK_SETTINGS_ID        = self.triggers_replace.network_settings_id
      APN_ORGANIZATION               = self.triggers_replace.organization
      APN_RUNNER_GROUP_ID            = self.triggers_replace.runner_group_id
    }
  }
}

resource "github_actions_hosted_runner" "this" {
  name              = local.names.runner
  size              = var.runner_size
  runner_group_id   = tonumber(github_actions_runner_group.this.id)
  maximum_runners   = var.maximum_runners
  public_ip_enabled = false
  image_version     = var.runner_image_version

  image {
    id     = var.runner_image_id
    source = var.runner_image_source
  }

  depends_on = [terraform_data.github_network_association]
}
