"""Deterministic contracts for the independent Foundry agent-to-Teams roots."""

from __future__ import annotations

import json
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
CATALOG = REPO / "examples" / "foundry-agent-teams"
OPTIONS = ("public", "standard-private-byor")
REQUIRED_ROOT_FILES = {
    "README.md",
    "bot_service.tf",
    "foundry.tf",
    "terraform.tfvars.example",
    "z_locals.tf",
    "z_outputs.tf",
    "z_variables.tf",
    "z_versions.tf",
}
REQUIRED_PAYLOADS = ("agent.json", "publish.json", "toolbox.json")
STALE_ENDPOINTS = ("agent-asset/v2.0", "api.azureml.ms/agent-asset")


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    assert (CATALOG / "README.md").is_file()

    roots: list[Path] = []
    for option in OPTIONS:
        root = CATALOG / option
        roots.append(root.resolve())
        files = {path.name for path in root.iterdir() if path.is_file()}
        assert REQUIRED_ROOT_FILES <= files, (option, REQUIRED_ROOT_FILES - files)
        assert (root / "tests" / "validation.tftest.hcl").is_file()

        for payload_name in REQUIRED_PAYLOADS:
            payload_path = root / "resources" / payload_name
            payload = json.loads(_text(payload_path))
            assert isinstance(payload, dict) and payload, payload_path

        combined = "\n".join(
            _text(path)
            for path in root.rglob("*")
            if path.is_file() and ".terraform" not in path.parts
        ).casefold()
        for stale_endpoint in STALE_ENDPOINTS:
            assert stale_endpoint not in combined, (root, stale_endpoint)

        terraform_source = "\n".join(_text(path) for path in root.glob("*.tf")).casefold()
        assert "local-exec" not in terraform_source
        assert 'provisioner "' not in terraform_source
        assert "avm-ptn-aiml-ai-foundry/azurerm" in combined
        assert "avm-res-botservice-botservice/azurerm" in combined
        assert "/agents/{name}/microsoft365/publish?api-version=v1" in combined
        assert "instance_identity.principal_id to bot service msaappid" in combined
        assert "do not substitute client_id" in combined
        assert "endpoint to remain the" in combined
        assert "agent activity-protocol url" in combined
        assert "publicnetworkaccess" in combined
        assert (
            "this setting does not disable" in combined
            or "bot service pna is still disabled" in combined
        )

    assert roots[0] != roots[1]
    for root in roots:
        for path in root.rglob("*"):
            assert not path.is_symlink(), path

    workflow = _text(REPO / ".github" / "workflows" / "foundry-agent-data-plane.yml")
    assert "id-token: write" in workflow
    assert "environment:" in workflow
    assert "microsoft365/publish?api-version=v1" in workflow
    assert "agent-handoff.auto.tfvars.json" in workflow
    assert "agent-asset/v2.0" not in workflow

    print("Foundry agent-to-Teams option contracts passed")


if __name__ == "__main__":
    main()