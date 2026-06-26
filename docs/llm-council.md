# LLM Council — advisory multi-model PR review

An optional, **advisory** review layer: on every pull request, 2-3 **distinct**
LLM models independently review the diff and a single consolidated verdict is
posted as a PR comment. It sits alongside the human gates (`CODEOWNERS`) and the
mechanical gates (OPA state-safety + governance) as the *AI-assisted* opinion —
a cheap second look that catches things a single reviewer (human or model)
misses, without becoming a bottleneck.

It is **not a merge gate by default.** The point is signal, not automation: a
human still approves. You can promote it to a required check (see *Make it a
gate* below) once you trust it for your repo.

## Why a "council" (multiple models)

A single model's verdict carries that model's training-distribution blind spots.
Asking three *different* model families the same question — independently, none
seeing the others' answers — gives a fast triangulation: where they agree you can
trust the signal; where they diverge is exactly the spot a human should look.
This is the same separation-of-duties logic as a human review panel.

## How it works

- [`.github/workflows/llm-council.yml`](../.github/workflows/llm-council.yml)
  runs on each PR (skipping drafts and bot authors).
- [`.github/scripts/llm-council.py`](../.github/scripts/llm-council.py) — a
  self-contained, **stdlib-only** script — fetches the diff, sends it to each
  configured model with an IaC-aware review rubric, parses each model's
  `VERDICT` (`APPROVE` / `COMMENT` / `BLOCK`) + one-line reason, and **upserts a
  single comment** on the PR (it edits its own prior comment rather than piling
  up new ones).
- It is **fail-soft**: if no backend is configured, or a model errors, it posts a
  short note and exits 0. It never breaks a PR.

## Default backend: GitHub Models (zero setup)

Out of the box it uses **GitHub Models** — no external accounts or keys. The
workflow already grants the `models: read` permission and passes the built-in
`GITHUB_TOKEN`. The default panel is three distinct families:

| Default model | Family |
|---|---|
| `openai/gpt-4o` | OpenAI |
| `meta/llama-3.3-70b-instruct` | Meta |
| `cohere/cohere-command-a` | Cohere |

Your org must have GitHub Models enabled. If it isn't, the council posts a
"could not run" note and passes — enable it, or switch providers below.
Model IDs come from the live catalog (`https://models.github.ai/catalog/models`)
and drift over time; verify the panel against it if a model 404s.

## Switch providers

Everything is configured with repo **Variables** (Settings → Secrets and
variables → Actions → Variables) and one **Secret**. All are optional.

| Setting | Where | Default | Notes |
|---|---|---|---|
| `COUNCIL_PROVIDER` | Variable | `github-models` | `github-models` \| `openai` \| `azure-openai` \| `anthropic` |
| `COUNCIL_MODELS` | Variable | per-provider | Comma-separated. For `azure-openai`, these are **deployment names**. |
| `COUNCIL_ENDPOINT` | Variable | per-provider | For `azure-openai`, the resource base, e.g. `https://my-aoai.openai.azure.com`. |
| `COUNCIL_API_VERSION` | Variable | `2024-10-21` | `azure-openai` only. |
| `COUNCIL_BLOCKING` | Variable | `false` | `true` → a `BLOCK` verdict fails the check. |
| `COUNCIL_MAX_DIFF_BYTES` | Variable | `60000` | Diff cap sent to the models. |
| `COUNCIL_API_KEY` | **Secret** | — | Required for `openai` / `azure-openai` / `anthropic`. `github-models` uses `GITHUB_TOKEN`. |

**Azure OpenAI example** (on-brand for an Azure repo — keeps inference in your
tenant): set `COUNCIL_PROVIDER=azure-openai`, `COUNCIL_ENDPOINT=https://<your>.openai.azure.com`,
`COUNCIL_MODELS=<deployment-a>,<deployment-b>`, and the `COUNCIL_API_KEY` secret.

## Make it a gate (optional)

The council ships advisory. To let a `BLOCK` actually stop a merge:

1. Set the `COUNCIL_BLOCKING` variable to `true` (a `BLOCK` verdict then fails
   the `llm-council` check).
2. In branch protection for `main`, add `llm-council` to the **required status
   checks**, and enable **Require review from Code Owners** + **Require branches
   to be up to date before merging**.
3. Keep `CODEOWNERS` covering `/.github/` — the shipped `CODEOWNERS` already does.

**Why step 3 is not optional:** a required check runs the *PR's own* copy of
`.github/scripts/llm-council.py`, so without protection a pull request could edit
the script to always pass and bypass the very gate it is supposed to enforce.
This caveat applies to **any** in-repo required check (terraform-validate,
policy-test, etc.), not just this one. `CODEOWNERS` on `/.github/` closes it: a PR
that touches the council's own workflow or script cannot merge without a Code
Owner's review, so the gate can't be silently neutered. Treat blocking mode as
defense-in-depth *behind* the human gate, never as a standalone control.

Keep `CODEOWNERS` as the human gate regardless — the council is a second
opinion, not a replacement for review.

## Security — secret handling

The workflow runs `.github/scripts/llm-council.py`, which lives in the repo and
can therefore be **modified by a pull request**. Treat the job's credentials
accordingly:

- **Fork PRs don't run it.** The job is gated to same-repo PRs
  (`head.repo.full_name == github.repository`). A fork PR gets a read-only
  `GITHUB_TOKEN` and no secrets, so it couldn't post a comment anyway — and no
  untrusted code ever runs with this job's token.
- **The default carries no standing secret.** GitHub Models uses only the
  scoped, ephemeral `GITHUB_TOKEN` (`models: read` + `pull-requests: write`),
  which expires with the run.
- **External-provider keys are an explicit opt-in.** `COUNCIL_API_KEY` is left
  commented out in the workflow on purpose — wiring a *standing* provider secret
  exposes it to the (same-repo) PR-controlled script. To use OpenAI / Azure
  OpenAI / Anthropic securely:
  1. Create a **GitHub Environment** (e.g. `llm-council`) holding the
     `COUNCIL_API_KEY` secret with **required reviewers**, so the key is released
     only after a human approves the run.
  2. In `llm-council.yml`, uncomment **both** the `environment:` binding on the
     job **and** the `COUNCIL_API_KEY:` line — an Environment secret only resolves
     in a job that declares `environment:`, so the binding is required, not
     optional.
  3. Keep `CODEOWNERS` on `/.github/` so changes to the council's own workflow or
     script are reviewed before they run.

  A plain repo/org secret also works *without* the `environment:` binding, but it
  is exposed to PR-controlled code on same-repo PRs — prefer the protected
  Environment.

## Data-governance note (read this for regulated / PHI environments)

This repo is built for **private, regulated (PHI / HIPAA / HITRUST)**
environments, so be deliberate: **the PR diff is sent to whichever LLM provider
you configure.** Before enabling the council on a repo that may contain sensitive
material:

- Prefer a provider with the data-handling guarantees your compliance baseline
  requires — typically **Azure OpenAI in your own tenant** (no training on your
  data, data stays in your boundary) over a shared public endpoint.
- Review what a diff can expose (config values, identifiers) and keep the diff
  cap (`COUNCIL_MAX_DIFF_BYTES`) tight.
- Treat enabling the council as a data-flow decision your security review signs
  off on, the same as any other outbound integration.

The default (GitHub Models) is convenient for trying the pattern; **validate its
data terms against your baseline before using it on sensitive repositories.**

## Customize the review

- **Models** — set `COUNCIL_MODELS` to your preferred panel (keep them from
  *different* families; that is the whole point).
- **Rubric** — edit `SYSTEM` / `RUBRIC` in
  [`.github/scripts/llm-council.py`](../.github/scripts/llm-council.py) to weight
  what your team cares about.
- **Scope** — the workflow's `paths:` limits it to `infra/`, `policy/`, and
  `.github/`. Widen or narrow to taste.

## Cost & latency

Three model calls per PR push (debounced — a new push cancels the in-flight run
via `concurrency`). On GitHub Models that is within the included allowance for
typical PR volume; on a paid provider it is a few cents per PR. The job adds tens
of seconds and never blocks (advisory), so it is off the critical path.
