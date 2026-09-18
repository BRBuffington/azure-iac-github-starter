output "foundry_resource_id" {
  description = "Private Foundry account resource ID; not a claim of data-plane readiness."
  value       = module.ai_foundry.ai_foundry_id
}

output "project_resource_id" {
  description = "Project resource ID for subsequent, separately owned application work."
  value       = module.ai_foundry.ai_foundry_project_id["runtime"]
}

output "runtime_store_ids" {
  description = "Dedicated runtime stores, not application export or ingestion stores."
  value = {
    storage = module.ai_foundry.storage_account_id["runtime"]
    cosmos  = module.ai_foundry.cosmos_db_id["runtime"]
    search  = module.ai_foundry.ai_search_id["runtime"]
  }
}