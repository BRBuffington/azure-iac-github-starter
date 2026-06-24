# Copilot instructions — Azure Landing Zone Terraform

Repo-scoped guidance so GitHub Copilot writes Terraform that matches this repo's
conventions. (GitHub Copilot reads `.github/copilot-instructions.md` automatically.)

## Conventions

- **Modules:** prefer Azure Verified Modules (https://aka.ms/avm) over hand-rolled
  `azurerm_*` resources. Cite the AVM module when you suggest one.
- **State:** the backend key is always nested `<prefix>/<scope>-<region>-<env>.tfstate`.
  Never propose a flat key, and never add a `terraform workspace` step (per-config key
  OR workspace, never both).
- **Config naming:** `infra/configs/<scope>-<region>-<env>.tfvars`; env suffix LAST.
  A security posture / feature flag is a variable in one config, not a second config.
- **Auth:** Entra/OIDC only (`use_azuread_auth = true`, `use_oidc = true`,
  `storage_use_azuread = true`). Never suggest storage access keys, client secrets,
  or `ARM_ACCESS_KEY`.
- **Identity model:** plan runs read-only (Reader + state read); apply runs scoped
  write, gated behind a GitHub Environment. Don't suggest broad Owner/Contributor at
  subscription scope.
- **Secrets:** source from Key Vault at runtime; never hard-code. Remember Terraform
  state stores values in plain text — don't put secrets in outputs or PR comments.

## Operating discipline (how to work, not just what to write)

- **Plan first.** For anything non-trivial, interview the user for the unknowns,
  then show the plan before you act. Never jump straight to `apply` — `plan` is a
  separate, reviewed step and the pipeline enforces that.
- **One change at a time.** Atomic commits; one feature per PR. Don't bundle
  unrelated changes — a small reviewable diff is the whole point of the gate.
- **Provenance is mandatory.** Every resource carries `DeployedByRepo` (via
  `local.common_tags`) and `lifecycle { ignore_changes = [tags["LastApplied"]] }`
  so the deployment is traceable and the post-apply stamp doesn't churn the plan.
- **Destroys stop.** Any plan that destroys or replaces a live resource halts for
  human review — the OPA state-safety gate fails it. Never set `allow_recreate`
  yourself; that is a human's call.
- **Decide once, then don't re-litigate.** Before making an architectural choice,
  read `docs/architecture-decisions.md` and `DECISIONS.md`. If a decision already
  covers it, follow it. When you make a new durable decision — or hit a gotcha
  worth not repeating — append it to `DECISIONS.md` so the next session inherits it
  instead of rediscovering it.

## What to do

- When asked to add a resource, suggest the AVM module first, wired to the existing
  `var.scope` / `var.region_alias` / `var.environment` naming.
- When editing pipelines, keep the flow scan -> init -> validate -> plan -> gated apply,
  and keep the OPA gate steps intact.

## What NOT to do

- Do not author anything that runs `apply` outside the pipeline.
- Do not relax the backend-key, OIDC, or no-shared-key invariants.
- Do not add a step that lets an agent approve its own PR or bypass the apply gate.
