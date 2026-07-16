from __future__ import annotations

import ast
import hashlib
import importlib.util
import sys
import types
import unittest
from pathlib import Path


ROOT = Path(__file__).parents[1]
SERVER_PATH = ROOT / "server.py"
DATA_PATH = ROOT / "guardrails.json"
EXPECTED_TOOLS = {
    "guardrails_manifest_get",
    "guardrails_release_get",
    "guardrails_naming_get",
    "guardrails_name_validate",
    "guardrails_requirement_list",
    "guardrails_control_explain",
    "guardrails_adr_get",
    "guardrails_review_checklist_get",
}


class _FakeFastMCP:
    def __init__(self, _name: str) -> None:
        pass

    def tool(self):
        return lambda function: function

    def run(self, **_kwargs) -> None:
        pass


def _load_server():
    fastmcp = types.ModuleType("mcp.server.fastmcp")
    fastmcp.FastMCP = _FakeFastMCP
    server_package = types.ModuleType("mcp.server")
    mcp_package = types.ModuleType("mcp")
    sys.modules["mcp"] = mcp_package
    sys.modules["mcp.server"] = server_package
    sys.modules["mcp.server.fastmcp"] = fastmcp

    spec = importlib.util.spec_from_file_location("guardrails_server", SERVER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def _decorated_tool_names() -> set[str]:
    tree = ast.parse(SERVER_PATH.read_text(encoding="utf-8"))
    names = set()
    for node in tree.body:
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        for decorator in node.decorator_list:
            if (
                isinstance(decorator, ast.Call)
                and isinstance(decorator.func, ast.Attribute)
                and decorator.func.attr == "tool"
            ):
                names.add(node.name)
    return names


class ReadOnlyContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = _load_server()

    def test_exposed_tools_match_exact_allowlist(self) -> None:
        self.assertEqual(EXPECTED_TOOLS, _decorated_tool_names())
        self.assertEqual(EXPECTED_TOOLS, set(self.server.READ_ONLY_TOOL_NAMES))

    def test_tool_names_expose_no_generic_or_mutating_capability(self) -> None:
        banned = {"apply", "create", "delete", "execute", "http", "secret", "shell", "update", "url", "write"}
        for tool_name in _decorated_tool_names():
            self.assertFalse(banned.intersection(tool_name.split("_")), tool_name)

    def test_every_tool_leaves_the_release_artifact_unchanged(self) -> None:
        before = DATA_PATH.read_bytes()
        calls = [
            lambda: self.server.guardrails_manifest_get(),
            lambda: self.server.guardrails_release_get("v0.1.0"),
            lambda: self.server.guardrails_naming_get("resource_group"),
            lambda: self.server.guardrails_name_validate("rg-app-eus-prd", "resource_group"),
            lambda: self.server.guardrails_requirement_list("terraform_pipeline"),
            lambda: self.server.guardrails_control_explain("CTL-ID-001"),
            lambda: self.server.guardrails_adr_get("ADR-001"),
            lambda: self.server.guardrails_review_checklist_get("terraform"),
        ]
        for call in calls:
            self.assertIsInstance(call(), dict)
        self.assertEqual(before, DATA_PATH.read_bytes())

    def test_manifest_reports_the_deployed_artifact_hash(self) -> None:
        expected = hashlib.sha256(DATA_PATH.read_bytes()).hexdigest()
        self.assertEqual(expected, self.server.guardrails_manifest_get()["artifact_sha256"])

    def test_name_validation_returns_actionable_findings(self) -> None:
        accepted = self.server.guardrails_name_validate("rg-app-eus-prd", "resource_group")
        rejected = self.server.guardrails_name_validate("bad_name", "resource_group")
        self.assertTrue(accepted["valid"])
        self.assertFalse(rejected["valid"])
        self.assertTrue(rejected["findings"])

    def test_unknown_identifiers_return_structured_errors(self) -> None:
        self.assertEqual(
            "control_not_found",
            self.server.guardrails_control_explain("CTL-UNKNOWN")["error"],
        )
        self.assertEqual(
            "checklist_not_found",
            self.server.guardrails_review_checklist_get("unknown")["error"],
        )


if __name__ == "__main__":
    unittest.main()