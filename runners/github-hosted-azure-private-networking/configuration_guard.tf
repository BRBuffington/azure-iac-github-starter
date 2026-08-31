check "subnet_capacity" {
  assert {
    condition     = local.runner_subnet_usable_addresses >= local.required_runner_addresses
    error_message = "runner_subnet_cidr must provide maximum_runners plus GitHub's 30 percent capacity buffer after Azure reserves five addresses."
  }
}

check "subnet_separation" {
  assert {
    condition     = var.runner_subnet_cidr != var.dependency_subnet_cidr
    error_message = "The delegated runner subnet and nondelegated dependency subnet must use different CIDRs."
  }
}

check "custom_image_version" {
  assert {
    condition     = var.runner_image_source == "custom" || var.runner_image_version == null
    error_message = "runner_image_version is valid only when runner_image_source is custom."
  }
}
