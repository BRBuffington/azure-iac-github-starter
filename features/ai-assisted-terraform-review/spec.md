# AI-assisted Terraform review implementation references

## Problem

The architecture guide described a phased adoption path but did not give an
engineer enough repository-native code and evidence steps to execute it. The
starter needs portable agent guidance, an exact read-only MCP contract, tests,
and a phase-by-phase implementation playbook without making AI authoritative.

## Requirements

- Provide repository-wide and Terraform-specific instructions that work across
  coding agents and degrade safely when an agent integration is absent.
- Provide a review skill that never applies infrastructure or approves its own
  change.
- Provide a runnable MCP sample with only the eight approved lookup/validation
  tools, no generic or mutation surface, and immutable release provenance.
- Contract-test the actual decorated tools, artifact immutability, structured
  errors, and real MCP SDK loading.
- Provide a detailed playbook with commands, linked files, exit evidence,
  rollback, preview/entitlement gates, and the Researcher automation boundary.
- Preserve deterministic checks, CODEOWNERS, environment approvals, and human
  authority as the required controls.

## Acceptance criteria

1. Removing the MCP sample causes its contract workflow to fail or disappear
   from the documented evidence path.
2. Adding a decorated mutation/generic tool fails the exact allowlist test.
3. Every current tool leaves the approved artifact byte-for-byte unchanged.
4. The sample imports and returns a manifest using the pinned MCP SDK.
5. Agent customization frontmatter contains no provider, required-model, or
   agent-specific tool gate.
6. Every adoption phase names executable files, commands, evidence, and rollback.
7. Existing Terraform, policy, and workflow validation remains green.

## Non-goals

- Deploying an Azure MCP runtime from this reference repository.
- Making Copilot, MCP, Researcher, or multi-model inference a required control.
- Encoding customer identifiers, topology, PHI, credentials, or state values.