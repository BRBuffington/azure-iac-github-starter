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
      condition     = local.approved_private_endpoint_target_keys_valid
      error_message = "Every approved key must identify a locally composed Private Endpoint target."
    }

    precondition {
      condition     = local.dns_publication_configuration_valid
      error_message = "prefixed_dns_zone_resource_group_id is required when approved targets publish DNS records."
    }

    precondition {
      condition     = local.enterprise_forwarding_valid
      error_message = "Supply both enterprise_forwarding_domain_name and enterprise_dns_server_ip_addresses, or neither."
    }
  }
}