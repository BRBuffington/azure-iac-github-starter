# State-safety gate (2 of 2): block a plan that would rebuild a live stack.
#
# Guards against the "plan ran against empty/wrong state and wants to recreate
# everything" failure (e.g. `Plan: 28 to add, 0 to change, 2 to destroy` on a
# stack that has been live for weeks). This is the mechanical backstop to a human
# pre-apply sanity check.
#
# Post-plan check. Operates on `terraform show -json` plan output.
#   input                       = the plan JSON (.resource_changes[])
#   data.params.allow_recreate  = operator override: the destroy/replace/large
#                                 first-apply is intentional and reviewed
#   data.params.destroy_mode    = the pipeline is running a `-destroy` plan
#                                 (deletes are expected)
#
# Absence of data.params = strict (overrides default false), so a missing params
# file fails safe (the guard stays active).
package main

import rego.v1

_override if data.params.allow_recreate == true

_override if data.params.destroy_mode == true

# Resource changes the plan would DELETE or REPLACE (replace == delete+create).
_destructive contains rc if {
	some rc in input.resource_changes
	rc.change.actions[_] == "delete"
}

deny contains msg if {
	not _override
	count(_destructive) > 0
	addrs := [rc.address | some rc in _destructive]
	msg := sprintf(
		"plan deletes/replaces %d resource(s): %v. On a live stack this is the empty/wrong-state signature — verify the backend key matches the live state BEFORE applying. Set allow_recreate=true only if the destruction is genuinely intended.",
		[count(_destructive), addrs],
	)
}

# Mass-create: a plan creating more than the threshold is the empty-state tell
# even when nothing is deleted (a routine change is a small diff).
_create_count := count([rc |
	some rc in input.resource_changes
	rc.change.actions[_] == "create"
])

_max_create := 20

deny contains msg if {
	not _override
	_create_count > _max_create
	msg := sprintf(
		"plan creates %d resources (threshold %d) — the empty/wrong-state rebuild signature. A routine change is a small diff. Set allow_recreate=true only for a genuine, reviewed first apply.",
		[_create_count, _max_create],
	)
}
