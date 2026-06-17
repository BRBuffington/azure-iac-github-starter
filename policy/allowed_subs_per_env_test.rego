package governance

import rego.v1

_plan(sub_expr) := {
	"configuration": {"provider_config": {"azurerm": {"expressions": {"subscription_id": sub_expr}}}},
	"variables": {"subscription_id": {"value": "aaaa1111-2222-3333-4444-555566667777"}},
	"resource_changes": [],
}

_params := {
	"environment": "prd",
	"allowed_subs_per_env": {
		"dev": ["dddd0000-0000-0000-0000-000000000000"],
		"prd": ["aaaa1111-2222-3333-4444-555566667777"],
	},
	"enforce_private_network": false,
	"enforce_secure_transport": false,
	"required_tags": [],
}

test_literal_sub_in_allowed_passes if {
	count(deny) == 0 with input as _plan({"constant_value": "aaaa1111-2222-3333-4444-555566667777"})
		with data.params as _params
}

test_literal_sub_not_allowed_denied if {
	count(deny) == 1 with input as _plan({"constant_value": "ffff9999-9999-9999-9999-999999999999"})
		with data.params as _params
}

test_var_reference_resolved_and_allowed if {
	count(deny) == 0 with input as _plan({"references": ["var.subscription_id"]})
		with data.params as _params
}

test_wrong_env_sub_denied if {
	# prd config pointed at the dev sub -> deny
	count(deny) == 1 with input as _plan({"constant_value": "dddd0000-0000-0000-0000-000000000000"})
		with data.params as _params
}

test_inert_when_env_has_no_mapping if {
	p := object.union(_params, {"environment": "sandbox"})
	count(deny) == 0 with input as _plan({"constant_value": "ffff9999-9999-9999-9999-999999999999"})
		with data.params as p
}
