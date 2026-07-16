# Implementation notes

## 2026-07-16 - Run Checkov natively on Container Apps job runners

The existing validation workflow used a Docker action, but the recommended Azure
Container Apps job runner cannot execute Docker commands. The workflow now installs
the action's pinned Checkov version as a Python CLI, preserving the same hard-fail
scan without requiring Docker-in-Docker.

## 2026-07-16 - Keep deployment out of the reference sample

The repository now proves the read-only application contract but does not create
an Azure runtime. Authentication, private networking, logging, and preview-risk
acceptance are environment-specific controls and must be designed before a host
is deployed; the playbook records their required evidence.

## 2026-07-16 - Use one exact eight-tool allowlist

The decorated FastMCP functions and the declared tool contract are compared in
tests. This makes an accidental generic or mutation tool a failing change rather
than a prompt-level promise.

## 2026-07-16 - Share rules through agent-neutral files

`AGENTS.md`, path instructions, and the review skill describe outcomes and use
generic commands. No model provider, client-specific tool prefix, or installed
agent is required, so missing integrations degrade to repository guidance.