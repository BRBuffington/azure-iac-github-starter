resource "terraform_data" "configuration_guard" {
  lifecycle {
    precondition {
      condition     = length(local.private_endpoint_targets) > 0
      error_message = "Set provider_storage_account_id, provider_sql_server_id, or both."
    }

    precondition {
      condition     = local.provider_resource_ids_valid
      error_message = "Provider resource IDs must identify an Azure Storage account or Azure SQL logical server."
    }

    precondition {
      condition     = local.standard_dns_configuration_valid
      error_message = "private_dns_zone_resource_group_id is required for every requested standard zone not supplied as an existing zone ID."
    }

    precondition {
      condition     = local.enterprise_forwarding_valid
      error_message = "Supply both enterprise_forwarding_domain_name and enterprise_dns_server_ip_addresses, or neither."
    }
  }
}