#!/usr/bin/env python3
"""Mutation-free MCP reference for centrally managed Terraform guardrails."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

from mcp.server.fastmcp import FastMCP


DATA_PATH = Path(__file__).with_name("guardrails.json")
IDENTIFIER_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
AZURE_NAME_PATTERN = re.compile(r"^[a-z0-9-]{1,90}$")

READ_ONLY_TOOL_NAMES = (
    "guardrails_manifest_get",
    "guardrails_release_get",
    "guardrails_naming_get",
    "guardrails_name_validate",
    "guardrails_requirement_list",
    "guardrails_control_explain",
    "guardrails_adr_get",
    "guardrails_review_checklist_get",
)

mcp = FastMCP("Terraform Guardrails (read-only)")


def _load_store() -> dict[str, Any]:
    with DATA_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def _identifier(value: str, field: str) -> str:
    if not IDENTIFIER_PATTERN.fullmatch(value):
        raise ValueError(f"{field} must match {IDENTIFIER_PATTERN.pattern}")
    return value


def _find_by_id(items: list[dict[str, Any]], item_id: str) -> dict[str, Any] | None:
    return next((item for item in items if item.get("id") == item_id), None)


@mcp.tool()
def guardrails_manifest_get() -> dict[str, Any]:
    """Return release provenance and the hash of the immutable artifact."""
    store = _load_store()
    return {
        "release": store["release"],
        "source_commit": store["source_commit"],
        "schema_version": store["schema_version"],
        "classification": store["classification"],
        "artifact_sha256": hashlib.sha256(DATA_PATH.read_bytes()).hexdigest(),
    }


@mcp.tool()
def guardrails_release_get(release_id: str) -> dict[str, Any]:
    """Return one approved release when it matches the deployed artifact."""
    release_id = _identifier(release_id, "release_id")
    store = _load_store()
    if release_id != store["release"]:
        return {"error": "release_not_found", "release_id": release_id}
    return {"manifest": guardrails_manifest_get(), "summary": store["release_summary"]}


@mcp.tool()
def guardrails_naming_get(resource_type: str, scope: str = "default") -> dict[str, Any]:
    """Return approved naming rules for a resource type and scope."""
    resource_type = _identifier(resource_type, "resource_type")
    scope = _identifier(scope, "scope")
    rules = _load_store()["naming_rules"].get(resource_type, [])
    return {"resource_type": resource_type, "scope": scope, "rules": rules}


@mcp.tool()
def guardrails_name_validate(
    name: str, resource_type: str, scope: str = "default"
) -> dict[str, Any]:
    """Evaluate a proposed Azure resource name without changing anything."""
    resource_type = _identifier(resource_type, "resource_type")
    scope = _identifier(scope, "scope")
    if not AZURE_NAME_PATTERN.fullmatch(name):
        return {
            "name": name,
            "resource_type": resource_type,
            "scope": scope,
            "valid": False,
            "findings": ["Name must contain only lowercase letters, numbers, and hyphens."],
        }

    rules = _load_store()["naming_rules"].get(resource_type, [])
    findings = [
        rule["message"]
        for rule in rules
        if not re.fullmatch(rule["pattern"], name)
    ]
    return {
        "name": name,
        "resource_type": resource_type,
        "scope": scope,
        "valid": not findings,
        "findings": findings,
    }


@mcp.tool()
def guardrails_requirement_list(
    resource_class: str, workload: str = "default"
) -> dict[str, Any]:
    """Return controls that apply to a resource class and workload."""
    resource_class = _identifier(resource_class, "resource_class")
    workload = _identifier(workload, "workload")
    controls = [
        control
        for control in _load_store()["controls"]
        if resource_class in control["applies_to"] or "*" in control["applies_to"]
    ]
    return {"resource_class": resource_class, "workload": workload, "controls": controls}


@mcp.tool()
def guardrails_control_explain(control_id: str) -> dict[str, Any]:
    """Explain one approved control with its source references."""
    control_id = _identifier(control_id, "control_id")
    control = _find_by_id(_load_store()["controls"], control_id)
    return control or {"error": "control_not_found", "control_id": control_id}


@mcp.tool()
def guardrails_adr_get(adr_id: str) -> dict[str, Any]:
    """Return one approved architecture decision record."""
    adr_id = _identifier(adr_id, "adr_id")
    adr = _find_by_id(_load_store()["adrs"], adr_id)
    return adr or {"error": "adr_not_found", "adr_id": adr_id}


@mcp.tool()
def guardrails_review_checklist_get(change_type: str = "terraform") -> dict[str, Any]:
    """Return the approved checklist for a Terraform change type."""
    change_type = _identifier(change_type, "change_type")
    checklist = _load_store()["review_checklists"].get(change_type)
    if checklist is None:
        return {"error": "checklist_not_found", "change_type": change_type}
    return {"change_type": change_type, "items": checklist}


if __name__ == "__main__":
    mcp.run(transport="streamable-http")