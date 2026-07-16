# Read-only Terraform guardrails MCP

This sample turns a reviewed, immutable `guardrails.json` release into eight
narrow lookup and validation tools. It is **structurally read-only**:

- no arbitrary URL, HTTP, shell, file, GitHub, ARM, secret, or Terraform tools;
- no write-capable identity or mutation method;
- a contract test compares the actual decorated tools to an exact allowlist;
- every tool call is tested to leave the release artifact byte-for-byte unchanged;
- every response can be traced to a release, source commit, and artifact hash.

The JSON file is a sanitized fixture. In production, build it from a reviewed,
tagged governance-repository release and deploy the artifact without an editing
path in the runtime.

## Run locally

```bash
python -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python server.py
```

The final command starts a Streamable HTTP MCP endpoint at the FastMCP default
address. A repository administrator can allowlist the exact tools in GitHub's
repository MCP configuration:

```json
{
  "mcpServers": {
    "terraform-guardrails": {
      "type": "http",
      "url": "https://guardrails.example.org/mcp",
      "tools": [
        "guardrails_manifest_get",
        "guardrails_release_get",
        "guardrails_naming_get",
        "guardrails_name_validate",
        "guardrails_requirement_list",
        "guardrails_control_explain",
        "guardrails_adr_get",
        "guardrails_review_checklist_get"
      ]
    }
  }
}
```

## Production hardening boundary

The local sample does not implement production authentication or networking.
Before serving topology-sensitive standards, deploy behind positive client
authentication, private networking and DNS, restricted egress, redacted
telemetry, an approved retention policy, and a reader-only runtime identity.
Keep Git-native instructions and deterministic checks available so an MCP
outage never blocks validation, merge, or apply.

GitHub Copilot code review currently supports MCP tools in public preview and
does not support OAuth-authenticated remote MCP servers. For a production pilot,
prefer a local bridge on an ephemeral in-VNet runner that signs in with OIDC;
use a rotating function key only for a time-bounded sanitized sandbox.