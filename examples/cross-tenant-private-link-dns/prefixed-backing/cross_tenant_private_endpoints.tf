# The AVM private endpoint module 0.2.0 hardcodes is_manual_connection=false.
# Cross-tenant consumers normally lack approval rights on the provider resource,
# so this focused raw AzureRM resource is required to create a pending request.
resource "azurerm_private_endpoint" "cross_tenant" {
  for_each = var.private_endpoint_targets

  name                = "pe-${var.name_prefix}-${replace(each.key, "_", "-")}"
  location            = var.location
  resource_group_name = var.private_endpoint_resource_group_name
  subnet_id           = var.private_endpoint_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name_prefix}-${replace(each.key, "_", "-")}"
    private_connection_resource_id = each.value.provider_resource_id
    subresource_names              = [each.value.subresource_name]
    is_manual_connection           = true
    request_message                = each.value.request_message
  }

  lifecycle {
    ignore_changes = [tags["LastApplied"]]
  }
}
