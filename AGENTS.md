# Agent operating contract

This repository is designed for GitHub Copilot, Claude Code, Codex, Gemini CLI,
and other coding agents. Agent-specific integrations are optional; the safety
and review rules below apply to every agent.

## Before changing infrastructure

1. Read `README.md`, `DECISIONS.md`, and `docs/architecture-decisions.md`.
2. Read `.github/copilot-instructions.md` and the matching path-scoped file in
   `.github/instructions/`, even when the current agent does not auto-load them.
3. Classify the proposed diff and any context sent to an AI service. Do not send
   PHI, secrets, state values, customer-confidential topology, or credentials.
4. State the intended change, affected state/config, validation steps, rollback,
   and any expected replacement or destroy before editing.

## Non-negotiable Terraform rules

- Prefer Azure Verified Modules and explain any direct `azurerm_*` resource.
- Use one nested backend key per config. Never combine per-config keys with
  Terraform workspaces.
- Use Entra ID and OIDC. Never add storage keys, client secrets, or long-lived
  cloud credentials.
- Keep plan and apply identities separate. Apply remains an explicit,
  human-approved GitHub Environment action.
- Preserve provenance tags and the OPA state-safety and governance gates.
- Never run or recommend local `terraform apply`.
- Stop on an unexpected destroy, replacement, state move, or scope expansion.

## Validation and review

- Use `.github/skills/terraform-review/SKILL.md` for every Terraform PR.
- Run the narrowest relevant checks first, then the repository workflows.
- Treat AI output as advisory. Deterministic validation, policy checks,
  `CODEOWNERS`, and environment approvers remain authoritative.
- Record durable choices and newly discovered failure modes in `DECISIONS.md`.

## Tool boundaries

- Agent tools may read source, plans, approved policy artifacts, and Azure
  metadata exposed through narrow read-only contracts.
- Do not expose generic shell, HTTP, file-write, secret, Terraform mutation, ARM
  mutation, or arbitrary URL tools to review agents.
- An unavailable MCP service must degrade to Git-native instructions and local
  deterministic checks; it must not block validation or authorize a bypass.