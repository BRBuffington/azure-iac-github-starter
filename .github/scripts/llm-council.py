#!/usr/bin/env python3
"""LLM Council — advisory, multi-model pull-request review (stdlib only).

Sends the PR diff to 2-3 DISTINCT LLM models in parallel-ish (sequential calls,
independent prompts), collects a structured verdict from each
(APPROVE / COMMENT / BLOCK + a one-line reason), and posts ONE consolidated
review comment on the PR. The models never see each other's verdicts, so the
three opinions are independent — the same separation-of-duties idea behind a
human review panel.

Design goals (this ships in a CLIENT-FACING template, so it is deliberately
small and dependency-free):

  * stdlib only (urllib) — no `pip install` step in CI.
  * Provider-pluggable. Ships defaulting to **GitHub Models** (zero external
    setup: uses the Actions `GITHUB_TOKEN` + the `models: read` permission).
    Swap to Azure OpenAI / OpenAI / Anthropic with two env vars.
  * Advisory by default — ALWAYS exits 0 so it never blocks a merge. Set
    `COUNCIL_BLOCKING=true` to exit non-zero on a BLOCK verdict so a branch-
    protection "required check" can gate on it.
  * Fail-soft — any provider / config / network error posts a short
    "council could not run" note and exits 0. An unconfigured backend must
    never break someone's PR.

Configuration (all via env; the workflow wires these up):

  COUNCIL_PROVIDER   github-models | openai | azure-openai | anthropic
                     (default: github-models)
  COUNCIL_MODELS     comma-separated model list (default: per-provider below)
  COUNCIL_ENDPOINT   override the provider's default endpoint. For azure-openai
                     this is the resource base, e.g.
                     https://my-aoai.openai.azure.com
  COUNCIL_API_KEY    key for openai / azure-openai / anthropic. github-models
                     uses GITHUB_TOKEN instead.
  COUNCIL_API_VERSION  azure-openai api-version (default 2024-10-21)
  COUNCIL_BLOCKING   "true" to fail the check on a BLOCK verdict (default false)
  COUNCIL_MAX_DIFF_BYTES  diff cap fed to the models (default 60000)

  GITHUB_TOKEN, GITHUB_REPOSITORY, PR_NUMBER, PR_TITLE, PR_AUTHOR — from CI.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

MARKER = "<!-- llm-council -->"
GITHUB_API = "https://api.github.com"
UA = "llm-council-action"

# ── Provider defaults ─────────────────────────────────────────────────────────
# Every provider is OpenAI Chat-Completions-compatible except Anthropic, which
# uses its own Messages API. Model names and endpoints DRIFT — these are sane
# defaults, all overridable via COUNCIL_MODELS / COUNCIL_ENDPOINT.
PROVIDER_DEFAULTS: dict[str, dict] = {
    "github-models": {
        # GitHub Models inference. Auth = the Actions GITHUB_TOKEN (needs the
        # `models: read` permission). Model names are `publisher/model`.
        "endpoint": "https://models.github.ai/inference/chat/completions",
        "models": [
            "openai/gpt-4o",
            "meta/llama-3.3-70b-instruct",
            "cohere/cohere-command-a",
        ],
    },
    "openai": {
        "endpoint": "https://api.openai.com/v1/chat/completions",
        "models": ["gpt-4o", "gpt-4o-mini"],
    },
    "azure-openai": {
        # COUNCIL_ENDPOINT = the resource base; COUNCIL_MODELS = deployment names.
        "endpoint": "",
        "models": [],
    },
    "anthropic": {
        "endpoint": "https://api.anthropic.com/v1/messages",
        "models": ["claude-3-5-sonnet-latest", "claude-3-5-haiku-latest"],
    },
}

SYSTEM = (
    "You are one independent reviewer on a multi-model review council for an "
    "Azure Infrastructure-as-Code (Terraform) repository. You review a single "
    "pull request and report concisely. You do not see the other reviewers' "
    "opinions — vote your own."
)

RUBRIC = """Review the pull-request diff below for:
- Correctness and idempotency.
- Security: secrets in code, public exposure, over-broad IAM/RBAC, missing
  private networking.
- Azure + Terraform best practice: CAF/WAF alignment, Azure Verified Modules,
  least privilege, tagging/provenance, no hardcoded regions/subscriptions.
- CI/CD safety and governance (state safety, gated apply, OPA policy).

Be specific — cite a file or hunk for each point. Keep it short.

End your review with EXACTLY these two lines and nothing after:
VERDICT: <APPROVE | COMMENT | BLOCK>
REASON: <one sentence>

APPROVE = no concerns. COMMENT = non-blocking suggestions only. BLOCK = a
concrete defect a maintainer must fix (cite the line)."""


# ── HTTP ──────────────────────────────────────────────────────────────────────
def _http(url, method="GET", headers=None, body=None, timeout=90):
    """Return (status, text). Network errors raise; HTTP error statuses are
    returned so the caller can read the error body."""
    if isinstance(body, (dict, list)):
        data = json.dumps(body).encode("utf-8")
    elif isinstance(body, str):
        data = body.encode("utf-8")
    else:
        data = None
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


# ── Model calls ───────────────────────────────────────────────────────────────
def _call_openai_compatible(endpoint, model, api_key, auth_mode, user_content):
    headers = {"Content-Type": "application/json", "User-Agent": UA}
    if auth_mode == "api-key":          # Azure OpenAI
        headers["api-key"] = api_key
    else:                                # bearer: github-models, openai
        headers["Authorization"] = f"Bearer {api_key}"
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user_content},
        ],
        "temperature": 0.2,
        "max_tokens": 1024,
    }
    status, text = _http(endpoint, "POST", headers, body)
    if status >= 300:
        raise RuntimeError(f"HTTP {status}: {text[:200]}")
    return json.loads(text)["choices"][0]["message"]["content"]


def _call_anthropic(endpoint, model, api_key, user_content):
    headers = {
        "Content-Type": "application/json",
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "User-Agent": UA,
    }
    body = {
        "model": model,
        "max_tokens": 1024,
        "system": SYSTEM,
        "messages": [{"role": "user", "content": user_content}],
    }
    status, text = _http(endpoint, "POST", headers, body)
    if status >= 300:
        raise RuntimeError(f"HTTP {status}: {text[:200]}")
    parts = json.loads(text).get("content", [])
    return "".join(p.get("text", "") for p in parts if p.get("type") == "text")


def call_model(provider, model, cfg, user_content):
    if provider == "anthropic":
        return _call_anthropic(cfg["endpoint"], model, cfg["api_key"], user_content)
    if provider == "azure-openai":
        ep = (f"{cfg['endpoint'].rstrip('/')}/openai/deployments/{model}"
              f"/chat/completions?api-version={cfg['api_version']}")
        return _call_openai_compatible(ep, model, cfg["api_key"], "api-key", user_content)
    return _call_openai_compatible(cfg["endpoint"], model, cfg["api_key"], "bearer", user_content)


# ── Verdict parsing ───────────────────────────────────────────────────────────
def parse_verdict(text):
    """Pull the trailing VERDICT/REASON out of a review. Falls back to COMMENT."""
    verdict, reason = "COMMENT", ""
    for line in text.splitlines():
        s = line.strip()
        up = s.upper()
        if up.startswith("VERDICT:"):
            v = up.split(":", 1)[1].strip()
            for cand in ("APPROVE", "BLOCK", "COMMENT"):
                if cand in v:
                    verdict = cand
                    break
        elif up.startswith("REASON:"):
            reason = s.split(":", 1)[1].strip()
    if not reason:
        # No explicit reason — use the first non-empty, non-verdict line.
        for line in text.splitlines():
            s = line.strip()
            if s and not s.upper().startswith(("VERDICT:", "REASON:")):
                reason = s[:200]
                break
    return verdict, reason


# ── Comment assembly ──────────────────────────────────────────────────────────
_BADGE = {"APPROVE": "APPROVE", "COMMENT": "COMMENT", "BLOCK": "BLOCK"}


def assemble_comment(provider, rows, errors, blocking):
    blocks = sum(1 for _, v, _, _ in rows if v == "BLOCK")
    approves = sum(1 for _, v, _, _ in rows if v == "APPROVE")
    posture = "blocking" if blocking else "advisory"
    head = (
        f"{MARKER}\n"
        f"## LLM Council review\n\n"
        f"_{len(rows)} model(s) via `{provider}` · {posture} · "
        f"{approves} approve / {blocks} block_\n\n"
        "| Model | Verdict | Reason |\n|---|---|---|\n"
    )

    def _esc(s):
        return (s or "—").replace("|", "\\|").replace("\n", " ").strip()

    table = "".join(
        f"| `{m}` | {_BADGE.get(v, v)} | {_esc(r)} |\n"
        for m, v, r, _ in rows
    )
    details = "\n".join(
        f"<details><summary><code>{m}</code> — {v}</summary>\n\n{full.strip()}\n\n</details>"
        for m, v, _, full in rows
    )
    foot = ""
    if errors:
        foot += ("\n\n> Some models did not respond: "
                 + "; ".join(errors) + ".")
    foot += ("\n\n<sub>Advisory multi-model review. Not a merge gate unless an "
             "adopter sets `COUNCIL_BLOCKING=true` and marks this a required "
             "check. See `docs/llm-council.md`.</sub>")
    return head + table + "\n" + details + foot


# ── GitHub plumbing ───────────────────────────────────────────────────────────
def _gh_headers(token):
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": UA,
        "Content-Type": "application/json",
    }


def fetch_diff(repo, pr, token, max_bytes):
    headers = _gh_headers(token)
    headers["Accept"] = "application/vnd.github.v3.diff"
    status, text = _http(f"{GITHUB_API}/repos/{repo}/pulls/{pr}", headers=headers)
    if status >= 300:
        raise RuntimeError(f"diff fetch HTTP {status}: {text[:160]}")
    if len(text.encode("utf-8")) > max_bytes:
        text = text.encode("utf-8")[:max_bytes].decode("utf-8", "ignore")
        text += "\n\n[... diff truncated for review ...]"
    return text


def post_comment(repo, pr, token, body):
    """Upsert the council comment (find by marker → PATCH, else POST).

    Pages through all PR comments so the marker upsert stays reliable on a busy
    PR with more than one page of comments (otherwise it would post a duplicate
    council comment instead of editing the existing one)."""
    page = 1
    while True:
        status, text = _http(
            f"{GITHUB_API}/repos/{repo}/issues/{pr}/comments?per_page=100&page={page}",
            headers=_gh_headers(token),
        )
        if status >= 300:
            break
        items = json.loads(text)
        for c in items:
            if MARKER in (c.get("body") or ""):
                _http(f"{GITHUB_API}/repos/{repo}/issues/comments/{c['id']}",
                      "PATCH", _gh_headers(token), {"body": body})
                return
        if len(items) < 100:
            break
        page += 1
    _http(f"{GITHUB_API}/repos/{repo}/issues/{pr}/comments",
          "POST", _gh_headers(token), {"body": body})


# ── Config resolution ─────────────────────────────────────────────────────────
def resolve_cfg(provider):
    d = dict(PROVIDER_DEFAULTS[provider])
    endpoint = os.environ.get("COUNCIL_ENDPOINT", "").strip() or d["endpoint"]
    models_env = os.environ.get("COUNCIL_MODELS", "").strip()
    models = [m.strip() for m in models_env.split(",") if m.strip()] or d["models"]
    if provider == "github-models":
        api_key = os.environ.get("GITHUB_TOKEN", "")
    else:
        api_key = os.environ.get("COUNCIL_API_KEY", "")
    return {
        "endpoint": endpoint,
        "models": models,
        "api_key": api_key,
        "api_version": (os.environ.get("COUNCIL_API_VERSION") or "2024-10-21").strip(),
    }


# ── Main ──────────────────────────────────────────────────────────────────────
def main(argv=None):
    ap = argparse.ArgumentParser(description="Advisory multi-model PR review.")
    ap.add_argument("--diff", help="path to a diff file (else fetched via API)")
    args = ap.parse_args(argv)

    repo = os.environ.get("GITHUB_REPOSITORY", "")
    pr = os.environ.get("PR_NUMBER", "")
    title = os.environ.get("PR_TITLE", "")
    token = os.environ.get("GITHUB_TOKEN", "")
    provider = (os.environ.get("COUNCIL_PROVIDER") or "github-models").strip()
    blocking = (os.environ.get("COUNCIL_BLOCKING") or "false").strip().lower() == "true"
    # Defensive parse: an operator typo on this optional var must not crash an
    # advisory check (fail-soft). Anything non-numeric falls back to the default.
    _raw_max = (os.environ.get("COUNCIL_MAX_DIFF_BYTES") or "60000").strip()
    max_bytes = int(_raw_max) if _raw_max.isdigit() else 60000

    if not (repo and pr and token):
        print("missing GITHUB_REPOSITORY / PR_NUMBER / GITHUB_TOKEN", file=sys.stderr)
        return 0  # fail-soft: nothing to do
    if provider not in PROVIDER_DEFAULTS:
        post_comment(repo, pr, token,
                     f"{MARKER}\n**LLM Council** skipped: unknown "
                     f"`COUNCIL_PROVIDER={provider}`. See `docs/llm-council.md`.")
        return 0

    cfg = resolve_cfg(provider)

    # Resolve the diff (file from CI, or fetch it ourselves).
    try:
        if args.diff and os.path.exists(args.diff):
            with open(args.diff, encoding="utf-8", errors="replace") as fh:
                diff = fh.read()
            if len(diff.encode("utf-8")) > max_bytes:
                diff = diff.encode("utf-8")[:max_bytes].decode("utf-8", "ignore")
                diff += "\n\n[... diff truncated for review ...]"
        else:
            diff = fetch_diff(repo, pr, token, max_bytes)
    except Exception as e:  # noqa: BLE001 — fail-soft
        print(f"diff resolution failed: {e}", file=sys.stderr)
        return 0
    if not diff.strip():
        post_comment(repo, pr, token, f"{MARKER}\n**LLM Council** — no reviewable diff.")
        return 0

    _DIFF = f"PR title: {title}\n\nDIFF:\n```diff\n{diff}\n```"
    user_content = RUBRIC + "\n\n" + _DIFF

    if provider != "github-models" and not cfg["api_key"]:
        post_comment(repo, pr, token,
                     f"{MARKER}\n**LLM Council** skipped: provider `{provider}` "
                     f"needs `COUNCIL_API_KEY`. See `docs/llm-council.md`.")
        return 0
    if not cfg["models"]:
        post_comment(repo, pr, token,
                     f"{MARKER}\n**LLM Council** skipped: no `COUNCIL_MODELS` set "
                     f"for provider `{provider}`. See `docs/llm-council.md`.")
        return 0

    rows, errors = [], []
    for model in cfg["models"]:
        try:
            text = call_model(provider, model, cfg, user_content)
            verdict, reason = parse_verdict(text)
            rows.append((model, verdict, reason, text))
        except Exception as e:  # noqa: BLE001 — one model failing is tolerable
            errors.append(f"`{model}`: {type(e).__name__}: {str(e)[:140]}")

    if not rows:
        post_comment(repo, pr, token,
                     f"{MARKER}\n**LLM Council** could not run (provider "
                     f"`{provider}`). Configure it — see `docs/llm-council.md`.\n\n- "
                     + "\n- ".join(errors or ["no models responded"]))
        return 0

    post_comment(repo, pr, token, assemble_comment(provider, rows, errors, blocking))

    if blocking and any(v == "BLOCK" for _, v, _, _ in rows):
        print("BLOCK verdict present and COUNCIL_BLOCKING=true — failing the check.")
        return 1
    return 0


if __name__ == "__main__":
    # Advisory contract: never red a PR on an internal error. main() returns 1
    # only intentionally (blocking mode + a BLOCK verdict); any unexpected
    # exception is logged and downgraded to a clean exit 0.
    try:
        _code = main()
    except Exception as _e:  # noqa: BLE001
        print(f"llm-council: unexpected error, exiting 0 (advisory): {_e}",
              file=sys.stderr)
        _code = 0
    raise SystemExit(_code)
