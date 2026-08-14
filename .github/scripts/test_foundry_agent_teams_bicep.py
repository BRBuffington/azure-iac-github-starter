"""Deterministic contracts for the private Foundry Bicep publication example."""

from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
ROOT = REPO / "examples" / "foundry-agent-teams" / "standard-private-bicep"


def _text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def main() -> None:
    publisher = _text(ROOT / "scripts" / "oneThroughFour.ps1")
    collector = _text(ROOT / "scripts" / "collect-network-diagnostics.ps1")
    readme = _text(ROOT / "README.md")
    readme_flat = " ".join(readme.split())

    for expected in (
        "version_selector",
        "Shared scope requires no admin approval",
        "evidence, not a root-cause classification",
        "cannot verify tenant-level Copilot extensibility",
        "response request ID",
    ):
        assert expected in publisher, expected

    for expected in (
        "networkInjections",
        "api-version=2025-04-01-preview",
        "Microsoft.App/environments",
        "private-endpoint-connection",
        "Foundry roles",
        "Bot roles",
        "remoteVirtualNetwork",
        "watcher', 'flow-log', 'list",
        "VNet flow logs are not retroactive",
        "New NSG flow logs are retired",
        "100.64.0.0/11",
        "100.100.0.0/17",
        "169.254.0.0/16",
    ):
        assert expected in collector, expected

    for mutation in (
        "watcher', 'flow-log', 'create",
        "watcher', 'flow-log', 'update",
        "watcher', 'flow-log', 'delete",
        "role', 'assignment', 'create",
        "provider', 'register",
    ):
        assert mutation not in collector, mutation

    for expected in (
        "collect-network-diagnostics.ps1",
        "VNet flow logs",
        "not retroactive",
        "active agent version",
        "do not identify the cause",
    ):
        assert expected in readme_flat, expected

    print("Foundry Bicep publication contracts passed")


if __name__ == "__main__":
    main()