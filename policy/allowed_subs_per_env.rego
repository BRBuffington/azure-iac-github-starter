# Subscription guardrail: deny a plan whose azurerm provider targets a
# subscription that is not on the approved list for the current environment.
# Catches the high-consequence misconfiguration of pointing a production config
# at a development subscription (or vice versa) through a wrong tfvars value.
#
# Ported from BRBuffington/terraform-opa-policies (post-plan/allowed_subs_per_env.rego),
# adapted to the conftest harness: the source reads `input.tfplan` + `data.shared`
# + a `tfrun` runtime object; here the plan JSON is `input` (from
# `terraform show -json`), the env is `data.params.environment`, and the per-env
# subscription map is `data.params.allowed_subs_per_env`. The provider
# subscription_id may be a literal or a `var.` reference, both resolved below
# (faithful to the source's eval_expression).
#
# Config (policy/governance.params.json):
#   "environment": "prd",
#   "allowed_subs_per_env": { "dev": ["<sub-guid>"], "prd": ["<sub-guid>"] }
#   (absent env key or empty map = inert)
package governance

import rego.v1

# Resolve the azurerm provider's configured subscription_id from the plan's
# configuration block: a literal constant_value, or a var.<name> reference
# resolved through the plan's top-level variables.
_provider_sub := val if {
	expr := input.configuration.provider_config.azurerm.expressions.subscription_id
	val := expr.constant_value
} else := val if {
	expr := input.configuration.provider_config.azurerm.expressions.subscription_id
	ref := expr.references[0]
	startswith(ref, "var.")
	var_name := replace(ref, "var.", "")
	val := input.variables[var_name].value
}

deny contains msg if {
	env := data.params.environment
	allowed := object.get(data.params.allowed_subs_per_env, env, [])
	count(allowed) > 0
	sub := _provider_sub
	not sub in allowed
	msg := sprintf(
		"subscription: azurerm provider targets subscription %q, which is not approved for environment %q (allowed: %v).",
		[sub, env, allowed],
	)
}
