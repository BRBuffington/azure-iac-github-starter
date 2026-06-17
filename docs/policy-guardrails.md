# Policy guardrails (OPA / conftest)

This repo gates the pipeline with [Open Policy Agent](https://www.openpolicyagent.org/)
policies evaluated by [conftest](https://www.conftest.dev/). There are two layers:

1. **State-safety** (always on) — prevents the highest-consequence Terraform mistakes.
2. **Governance** (opt-in per guardrail) — data-residency, tagging, subscription,
   and network-posture controls.

All policies are unit-tested (`opa test policy/`, run in CI by `policy-test.yml`).

## How it runs

- **CD** (`terraform-cd.yml`): after `terraform plan`, the plan is rendered to JSON
  (`terraform show -json`) and evaluated against **both** the `main` (state-safety) and
  `governance` namespaces. A deny fails the run before any apply.
- **PR** (`terraform-validate.yml`): the governance namespace runs on the speculative
  plan so violations surface in review (shift-left).
- Config comes from `policy/governance.params.json`, merged at runtime into the data
  document `data.params` (conftest namespaces a `--data` file by basename, so the file
  the workflow writes is `params.json`).

## State-safety policies (always on)

| Policy | Package | What it denies |
|---|---|---|
| `backend_key.rego` | `backend_key` | A backend state key that isn't `<prefix>/<config>.tfstate` (a flat/laptop key diverges from the CD per-config blob and makes plans run against empty state). |
| `no_unexpected_destroy.rego` | `main` | A plan that deletes/replaces live resources, or mass-creates (> 20) against empty/wrong state — the "rebuild the whole stack" signature. Override a genuine destructive change with `allow_recreate`. |

## Governance pack (opt-in via `governance.params.json`)

Every governance guardrail is **inert until configured**, so the repo ships safe to run.

| Policy | Denies | Turn on by setting |
|---|---|---|
| `allowed_regions.rego` | A resource targeting a region outside the approved list (data residency). | `allowed_regions: ["eastus", ...]` |
| `required_tags.rego` | A resource group (or any `tag_enforced_types`) missing a required tag, or with a tag value outside its allowed set. | `required_tags: [...]`, optionally `tag_allowed_values: {...}` |
| `allowed_subs_per_env.rego` | A plan whose azurerm provider targets a subscription not approved for the current environment (deploy-to-wrong-sub guard). | `environment` + `allowed_subs_per_env: {env: [subId]}` |
| `deny_public_network_access.rego` | A resource left with public network access enabled (enforces the private-endpoint posture). **On by default.** | `enforce_private_network: true` (default) |
| `require_secure_transport.rego` | A storage account allowing HTTP or TLS < 1.2 (encryption in transit). **On by default.** | `enforce_secure_transport: true` (default) |

## Provenance

`allowed_regions`, `required_tags`, and `allowed_subs_per_env` are ported from the
internal `terraform-opa-policies` policy library, adapted to this repo's conftest
harness (the source evaluates `input.tfplan` + `data.shared` with a `tfrun` runtime
object and pre-`rego.v1` syntax; here the plan JSON is `input`, config is
`data.params`, and policies use `import rego.v1`). The source's richer semantics —
tag-value validation and the per-environment subscription map — are preserved.
`deny_public_network_access` and `require_secure_transport` are new, added to enforce
the private-endpoint and encryption-in-transit posture this reference recommends.

## Adding your own guardrail

1. Add `policy/<name>.rego` in `package governance`, reading config from `data.params`
   and gating on a param so it stays inert when unconfigured. Reuse the
   `managed_resources` helper in `governance_common.rego` (it yields create/update
   resource changes).
2. Add `policy/<name>_test.rego` with `opa test`-style cases (use a file-unique helper
   name — all governance tests share one package).
3. Document it in the table above and add its parameter to `governance.params.json`.
4. `opa test policy/` must stay green.
