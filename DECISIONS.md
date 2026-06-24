# Decisions & learned guardrails

A living, append-only record the agent — and humans — read **before** making a
choice, so a decision is made once, not re-litigated every session. This is the
operational companion to [`docs/architecture-decisions.md`](docs/architecture-decisions.md)
(the big, cited architecture decisions): this file captures the smaller,
accumulating decisions and the gotchas you hit along the way.

> **Agent:** read this file before any non-trivial change. If a decision below
> already covers what you're about to do, follow it. After you make a new durable
> decision — or hit a gotcha worth not repeating — append an entry here.

## Decisions

Newest first. One entry per decision: `### YYYY-MM-DD — summary`, then 1–3
sentences of *why*.

### YYYY-MM-DD — (example) chose Function App over Container App for the shared MCP host
The agent's first instinct was a Container App, but a Function App is cheaper and
sufficient for a lightweight, mostly-static server. Recorded so the next session
doesn't re-open the same choice. *(Delete this seed entry once you have real ones.)*

## Learned guardrails (anti-patterns — don't repeat)

Things that bit us once. Each: the symptom, then the rule that prevents it.

### (example) The agent re-created infrastructure it had already deployed
**Symptom:** the agent couldn't find a resource it built weeks earlier and
proposed re-creating it — it took three reminders. **Rule:** every resource
carries a `DeployedByRepo` tag + a post-apply `LastApplied` stamp (see
`infra/locals.tf` and the CD stamp step) so prior work is traceable off the
resource itself, and the agent reads this file before deciding. *(Delete once you
have real ones.)*
