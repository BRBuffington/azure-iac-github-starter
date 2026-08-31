resource "terraform_data" "configuration_guard" {
  input = {
    dependency_subnet_cidr = var.dependency_subnet_cidr
    maximum_runners        = var.maximum_runners
    runner_subnet_cidr     = var.runner_subnet_cidr
  }

  lifecycle {
    precondition {
      condition     = local.runner_subnet_usable_addresses >= local.required_runner_addresses
      error_message = "runner_subnet_cidr must provide maximum_runners plus GitHub's 30 percent capacity buffer after Azure reserves five addresses."
    }

    precondition {
      condition = (
        local.runner_subnet_last < local.dependency_subnet_first ||
        local.dependency_subnet_last < local.runner_subnet_first
      )
      error_message = "The delegated runner subnet and nondelegated dependency subnet must not overlap."
    }

    precondition {
      condition     = var.runner_image_source == "custom" || var.runner_image_version == null
      error_message = "runner_image_version is valid only when runner_image_source is custom."
    }
  }
}
