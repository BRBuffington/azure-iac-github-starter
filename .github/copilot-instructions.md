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

## What to do

- When asked to add a resource, suggest the AVM module first, wired to the existing
  `var.scope` / `var.region_alias` / `var.environment` naming.
- When editing pipelines, keep the flow scan -> init -> validate -> plan -> gated apply,
  and keep the OPA gate steps intact.

## What NOT to do

- Do not author anything that runs `apply` outside the pipeline.
- Do not relax the backend-key, OIDC, or no-shared-key invariants.
- Do not add a step that lets an agent approve its own PR or bypass the apply gate.
