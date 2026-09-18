resource "azurerm_monitor_diagnostic_setting" "blob" {
  for_each = local.blob_diagnostics

  name                           = "diag-${local.prefix}-blob"
  target_resource_id             = "${module.ai_foundry.storage_account_id[each.key]}/blobServices/default"
  log_analytics_workspace_id     = var.log_analytics_workspace_resource_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = each.value

    content {
      category = enabled_log.value
    }
  }
}