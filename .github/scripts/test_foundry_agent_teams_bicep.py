"""Compiled contracts for the independent Foundry agent-to-Teams Bicep root."""

from __future__ import annotations

import json
import re
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "examples" / "foundry-agent-teams" / "standard-private-bicep"
ROLE_IDS = (
    "53ca6127-db72-4b80-b1b0-d745d6d5456d",  # Foundry User
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe",  # Storage Blob Data Contributor
    "b7e6dc6d-f1e8-4753-8033-0f276bb0955b",  # Storage Blob Data Owner
    "230815da-be43-4aae-9cb4-875f7bd000aa",  # Cosmos DB Operator
    "8ebe5a00-799e-43f5-93ac-243d3dce84a7",  # Search Index Data Contributor
    "7ca78c08-252a-4471-8644-bb5ff32d4ba0",  # Search Service Contributor
    "00000000-0000-0000-0000-000000000002",  # Cosmos DB data contributor
)
EXAMPLE_SUBSCRIPTION_ID = "00000000-0000-0000-0000-000000000000"
GUID_PATTERN = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    required_files = {
        ".gitignore",
        "README.md",
        "THIRD-PARTY-NOTICES.md",
        "main.bicep",
        "main.bicepparam",
    }
    actual_files = {path.name for path in ROOT.iterdir() if path.is_file()}
    assert required_files <= actual_files, required_files - actual_files
    assert (ROOT / "scripts" / "invoke-agent-publication.ps1").is_file()
    assert (ROOT / "scripts" / "lib" / "azure-cli.ps1").is_file()

    for path in ROOT.rglob("*"):
        assert not path.is_symlink(), path

    combined = "\n".join(_text(path) for path in ROOT.rglob("*") if path.is_file())
    allowed_guids = {EXAMPLE_SUBSCRIPTION_ID, *ROLE_IDS}
    unexpected_guids = {
        match.group(0).casefold()
        for match in GUID_PATTERN.finditer(combined)
        if match.group(0).casefold() not in allowed_guids
    }
    assert not unexpected_guids, unexpected_guids

    bicep = "\n".join(_text(path) for path in ROOT.rglob("*.bicep"))
    bicep_folded = bicep.casefold()
    for contract in (
        "networkinjections",
        "scenario: 'agent'",
        "subnetarmid: agentsubnetresourceid",
        "publicnetworkaccess: 'disabled'",
        "disablelocalauth: true",
        "defaultaction: 'deny'",
        "category: 'azurestorageaccount'",
        "category: 'cosmosdb'",
        "category: 'cognitivesearch'",
        "capabilityhostkind: 'agents'",
        "microsoft.network/privateendpoints@",
        "groupids:",
        "'account'",
        "'blob'",
        "'sql'",
        "'searchservice'",
        "microsoft.botservice/botservices@",
        "publicnetworkaccess: 'disabled'",
        "msaapptype: 'singletenant'",
        "microsoft.botservice/botservices/channels@",
        "channelname: 'msteamschannel'",
    ):
        assert contract in bicep_folded, contract

    for role_id in ROLE_IDS:
        assert role_id in bicep_folded, role_id
    assert not list(ROOT.rglob("*.tf"))

    agent_payload = json.loads(_text(ROOT / "resources" / "agent.json"))
    publish_payload = json.loads(_text(ROOT / "resources" / "publish.json"))
    assert agent_payload["definition"]["kind"] == "prompt"
    assert agent_payload["definition"]["tools"] == []
    assert publish_payload["publishScope"] == "Shared"
    assert publish_payload["publishAsAutopilot"] is False

    publication = _text(ROOT / "scripts" / "invoke-agent-publication.ps1")
    publication_folded = publication.casefold()
    assert "[switch]$execute" in publication_folded
    assert "if (-not $execute)" in publication_folded
    assert "timeoutsec = $timeoutseconds" in publication_folded
    assert "account.user.type -ne 'user'" in publication_folded
    assert "microsoft365/publish?api-version=v1" in publication_folded
    assert "agent-handoff.parameters.json" in publication_folded
    assert "publicnetworkaccess must remain disabled" in publication_folded
    assert "botservicetenant" in publication_folded
    assert "channels/msteamschannel" in publication_folded
    assert "msaapptenantid" in publication_folded
    for forbidden_write in (
        "'group', 'create'",
        "'resource', 'create'",
        "'resource', 'update'",
        "'network', 'vnet', 'create'",
        "az rest",
        "new-az",
    ):
        assert forbidden_write not in publication_folded, forbidden_write

    azure_cli = _text(ROOT / "scripts" / "lib" / "azure-cli.ps1")
    assert "WaitForExit($TimeoutSeconds * 1000)" in azure_cli
    assert "Kill($true)" in azure_cli
    assert "ReadToEndAsync()" in azure_cli

    print("Foundry agent-to-Teams Bicep contracts passed")


if __name__ == "__main__":
    main()