variable "subscription_id" {
  description = "Azure subscription that contains the runner VNet and NetworkSettings resource."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be an Azure subscription UUID."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the runner networking resources."
  type        = string

  validation {
    condition     = trimspace(var.resource_group_name) != ""
    error_message = "resource_group_name must be non-empty."
  }
}

variable "location" {
  description = "Azure region supported by GitHub-hosted runner private networking."
  type        = string

  validation {
    condition     = trimspace(var.location) != ""
    error_message = "location must be non-empty."
  }
}

variable "scope" {
  description = "Short workload scope used in resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,15}$", var.scope))
    error_message = "scope must be 2-16 lowercase letters, numbers, or hyphens."
  }
}

variable "region_alias" {
  description = "CAF-style region alias such as eus, eus2, cus, or wus3."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.region_alias))
    error_message = "region_alias must be 2-6 lowercase letters or numbers."
  }
}

variable "environment" {
  description = "Environment suffix. Deploy each environment from its own state."
  type        = string

  validation {
    condition     = contains(["dev", "tst", "si", "qa", "uat", "prd", "dr"], var.environment)
    error_message = "environment must be one of dev, tst, si, qa, uat, prd, or dr."
  }
}

variable "vnet_address_space" {
  description = "Address space for the environment-specific runner VNet."
  type        = string

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR."
  }
}

variable "runner_subnet_cidr" {
  description = "CIDR for the subnet delegated to GitHub.Network/networkSettings."
  type        = string

  validation {
    condition     = can(cidrhost(var.runner_subnet_cidr, 0))
    error_message = "runner_subnet_cidr must be a valid CIDR."
  }
}

variable "dependency_subnet_cidr" {
  description = "CIDR for approved private endpoints. No endpoints are created by this root."
  type        = string

  validation {
    condition     = can(cidrhost(var.dependency_subnet_cidr, 0))
    error_message = "dependency_subnet_cidr must be a valid CIDR."
  }
}

variable "route_table_resource_id" {
  description = "Existing route table that sends runner and dependency traffic through the approved egress path."
  type        = string

  validation {
    condition     = can(regex("(?i)^/subscriptions/.+/resourceGroups/.+/providers/Microsoft.Network/routeTables/.+$", var.route_table_resource_id))
    error_message = "route_table_resource_id must be a complete Azure route table resource ID."
  }
}

variable "approved_private_dependencies" {
  description = "Named runner-to-private-endpoint NSG rules. Keep empty until each destination and data-plane operation is approved."
  type = map(object({
    destination_address_prefixes = set(string)
    destination_port_ranges      = set(string)
  }))
  default = {}

  validation {
    condition = length(var.approved_private_dependencies) <= 100 && alltrue([
      for name, dependency in var.approved_private_dependencies :
      can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", name)) &&
      length(dependency.destination_address_prefixes) > 0 &&
      length(dependency.destination_port_ranges) > 0
    ])
    error_message = "Each approved dependency needs a short alphanumeric name and at least one destination prefix and port range."
  }
}

variable "dns_servers" {
  description = "Optional DNS server addresses used by the runner VNet."
  type        = list(string)
  default     = []
}

variable "github_organization" {
  description = "GitHub organization login that owns the runner group."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", var.github_organization))
    error_message = "github_organization must be a valid GitHub organization login."
  }
}

variable "selected_repositories" {
  description = "Repository names in github_organization allowed to schedule the runner group."
  type        = set(string)

  validation {
    condition = length(var.selected_repositories) > 0 && alltrue([
      for name in var.selected_repositories : can(regex("^[A-Za-z0-9_.-]{1,100}$", name))
    ])
    error_message = "selected_repositories must contain at least one valid repository name without the organization prefix."
  }
}

variable "selected_workflows" {
  description = "Fully qualified workflows allowed to schedule the runner group."
  type        = set(string)

  validation {
    condition = length(var.selected_workflows) > 0 && alltrue([
      for workflow in var.selected_workflows :
      can(regex("^[^/]+/[^/]+/\\.github/workflows/[^@]+@\\S+$", workflow))
    ])
    error_message = "selected_workflows must contain fully qualified workflow refs."
  }
}

variable "runner_image_id" {
  description = "GitHub-hosted runner image ID. Defaults to GitHub's latest stable Ubuntu image."
  type        = string
  default     = "ubuntu-latest"

  validation {
    condition     = trimspace(var.runner_image_id) != ""
    error_message = "runner_image_id must be non-empty."
  }
}

variable "runner_image_source" {
  description = "GitHub-hosted runner image source."
  type        = string
  default     = "github"

  validation {
    condition     = contains(["github", "partner", "custom"], var.runner_image_source)
    error_message = "runner_image_source must be github, partner, or custom."
  }
}

variable "runner_image_version" {
  description = "Optional image version for custom images."
  type        = string
  default     = null
  nullable    = true
}

variable "runner_size" {
  description = "Machine size returned by the GitHub hosted-runners machine-sizes API."
  type        = string
  default     = "4-core"
}

variable "maximum_runners" {
  description = "Maximum concurrent runners in this pool."
  type        = number
  default     = 10

  validation {
    condition     = var.maximum_runners >= 1 && floor(var.maximum_runners) == var.maximum_runners
    error_message = "maximum_runners must be a positive integer."
  }
}

variable "deployed_by_repo" {
  description = "Repository recorded in Azure provenance tags, for example ORG/REPO."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.deployed_by_repo))
    error_message = "deployed_by_repo must use ORG/REPO format."
  }
}

variable "tags" {
  description = "Additional Azure resource tags."
  type        = map(string)
  default     = {}
}

variable "enable_telemetry" {
  description = "Controls AVM telemetry."
  type        = bool
  default     = true
}
