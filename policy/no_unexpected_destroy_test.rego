package main

import rego.v1

# A routine small create-only plan passes
test_small_create_allowed if {
	count(deny) == 0 with input as {"resource_changes": [
		{"address": "azurerm_resource_group.this", "change": {"actions": ["create"]}},
		{"address": "azurerm_storage_account.this", "change": {"actions": ["create"]}},
	]}
		with data.params as {"allow_recreate": false}
}

# A no-op plan passes
test_noop_allowed if {
	count(deny) == 0 with input as {"resource_changes": [{"address": "azurerm_resource_group.this", "change": {"actions": ["no-op"]}}]}
		with data.params as {"allow_recreate": false}
}

# A delete is denied
test_delete_denied if {
	count(deny) > 0 with input as {"resource_changes": [{"address": "azurerm_resource_group.this", "change": {"actions": ["delete"]}}]}
		with data.params as {"allow_recreate": false}
}

# A replace (delete+create) is denied
test_replace_denied if {
	count(deny) > 0 with input as {"resource_changes": [{"address": "azurerm_role_assignment.x", "change": {"actions": ["delete", "create"]}}]}
		with data.params as {"allow_recreate": false}
}

# Mass-create (> 20) is denied
test_mass_create_denied if {
	changes := [{"address": sprintf("azurerm_x.n%d", [i]), "change": {"actions": ["create"]}} | some i in numbers.range(1, 21)]
	count(deny) > 0 with input as {"resource_changes": changes}
		with data.params as {"allow_recreate": false}
}

# allow_recreate override clears a destructive plan
test_allow_recreate_overrides_delete if {
	count(deny) == 0 with input as {"resource_changes": [{"address": "azurerm_resource_group.this", "change": {"actions": ["delete"]}}]}
		with data.params as {"allow_recreate": true}
}

# destroy_mode override clears deletes
test_destroy_mode_overrides_delete if {
	count(deny) == 0 with input as {"resource_changes": [{"address": "azurerm_resource_group.this", "change": {"actions": ["delete"]}}]}
		with data.params as {"destroy_mode": true}
}

# Missing params = fail-safe (guard stays active)
test_missing_params_still_denies_delete if {
	count(deny) > 0 with input as {"resource_changes": [{"address": "azurerm_resource_group.this", "change": {"actions": ["delete"]}}]}
}
