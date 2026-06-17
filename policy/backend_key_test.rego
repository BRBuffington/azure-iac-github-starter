package backend_key

import rego.v1

# Valid nested per-config keys
test_nested_key_allowed if {
	count(deny) == 0 with input as {"key": "platform/hub-eus-prd.tfstate"}
}

test_multi_level_prefix_allowed if {
	count(deny) == 0 with input as {"key": "team/platform/hub-eus-prd.tfstate"}
}

test_mixed_case_allowed if {
	count(deny) == 0 with input as {"key": "MyStack/Hub-Eus-Prd.tfstate"}
}

# Invalid flat keys (the bug this guards)
test_flat_key_denied if {
	count(deny) == 1 with input as {"key": "hub.tfstate"}
}

test_no_tfstate_suffix_denied if {
	count(deny) == 1 with input as {"key": "platform/hub-eus-prd"}
}

test_empty_key_denied if {
	count(deny) == 1 with input as {"key": ""}
}
