---
name: terraform-review
description: Review Azure Terraform pull requests for correctness, state safety, identity boundaries, policy compliance, and operational evidence. Use for every change under infra/, policy/, or Terraform delivery workflows. Never apply infrastructure.
---

# Terraform review

Produce an evidence-first review of an Azure Terraform change. This skill is
agent-neutral: use the available file, search, Git, and command tools on the
current client. The review is advisory and never authorizes merge or apply.

## 1. Establish the contract

Read `AGENTS.md`, `.github/copilot-instructions.md`,
`.github/instructions/terraform.instructions.md`, `DECISIONS.md`, and the
changed files. Identify:

- target environment, subscription scope, backend key, and config file;
- expected resources and intended state transitions;
- data classification and whether plan or state content can leave the tenant;
- identities used for plan and apply;
- explicit rollback and any approved replacement or destroy.

If any item is unknown, report it as a blocking question. Do not infer approval.

## 2. Run deterministic checks

Run the repository's existing commands and workflows rather than inventing a
parallel validation path. At minimum:

```bash
terraform -chdir=infra fmt -check -recursive
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
python -m unittest discover -s examples/read-only-guardrails-mcp/tests -v
```

Also require Checkov, OPA/conftest policy tests, and the speculative plan from
the pull-request workflow. A missing, empty, crashed, or unparseable check is a
failure, never a pass.

## 3. Inspect the change by risk

Review the source and plan for:

1. **State safety:** nested backend key, no workspace, correct state lineage,
   no empty-state rebuild signature, and no unapproved migration.
2. **Identity:** OIDC only, separate plan/apply principals, least-privilege
   scopes, no current-applier-derived operator grants, and no standing secret.
3. **Destructive actions:** explain every delete, replacement, move, or import.
   Stop when approval evidence is absent.
4. **Security:** private networking defaults, managed identity, secure transport,
   secret handling, diagnostic coverage, and retention.
5. **Governance:** allowed region/subscription, required tags, naming rules,
   policy exceptions, provenance, and decision-log consistency.
6. **Operations:** dependency ordering, failure recovery, idempotency, drift
   behavior, and rollback.
7. **AI boundary:** no PHI, credentials, state values, sensitive topology, or
   confidential content in prompts, comments, logs, fixtures, or model inputs.

## 4. Report findings first

Order findings by severity: blocker, major, then minor. For each finding include:

- the exact file and relevant line or plan address;
- the observable failure or risk;
- the evidence that demonstrates it;
- the smallest corrective action.

Then list open questions, checks executed with their result, and residual risks.
If there are no findings, say so explicitly and identify any check that could not
be run. Never describe a skipped or unavailable check as successful.

## 5. Preserve human authority

Do not approve the pull request, alter branch protection, set an apply flag,
approve an environment, bypass `CODEOWNERS`, or run Terraform apply. Human
reviewers and deterministic gates decide whether the change advances.