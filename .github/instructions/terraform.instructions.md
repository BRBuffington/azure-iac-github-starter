---
description: Path-scoped rules for Azure Terraform modules, configs, and backends.
applyTo: "infra/**/*.{tf,tfvars}"
---

# Azure Terraform implementation rules

## Module and resource design

- Start with the current Azure Verified Module for the resource type. Pin the
  module version and document why a direct `azurerm_*` resource is necessary.
- Follow the repository's existing variable, local, output, and config shape.
  Do not introduce a second naming system or environment-selection mechanism.
- Keep resource names deterministic from `scope`, `region_alias`, and
  `environment`; do not depend on runtime timestamps or random values unless the
  service requires global uniqueness.

## State and identity

- The backend key is `<prefix>/<scope>-<region>-<env>.tfstate`.
- Use `use_azuread_auth = true` and `use_oidc = true`. Do not use access keys,
  SAS tokens, service-principal secrets, or `ARM_ACCESS_KEY`.
- Never add `terraform workspace` commands when the backend already separates
  configs by key.
- Keep operator access bound to an explicit stable principal. Never derive a
  human/operator grant from the identity currently running `terraform apply`.

## Security and operability

- Default supported services to private networking, managed identity, secure
  transport, diagnostic settings, and explicit retention where the module
  exposes those controls.
- Secrets come from Key Vault at runtime. Do not output secrets or place them in
  state-derived comments, plans, logs, examples, or fixtures.
- Apply `local.common_tags`, including deployment provenance. Preserve
  `ignore_changes` for the CI-managed `LastApplied` tag.
- Make destructive behavior visible. Do not add lifecycle suppression that hides
  a replacement, and never set an `allow_recreate` approval in code.

## Evidence before approval

For every changed config, produce evidence for formatting, backend-free
initialization, validation, security scanning, policy tests, and the speculative
plan when a backend is configured. Explain every create, update, replace, and
destroy in the plan before recommending approval.