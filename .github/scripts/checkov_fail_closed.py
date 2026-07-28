#!/usr/bin/env python3
"""Run Checkov and fail closed on incomplete or invalid scan results."""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
from typing import Any

_DOWNLOAD_FAILURE = "failed to download module"


def assess_result(returncode: int, stdout: str, stderr: str) -> tuple[bool, str]:
    if returncode != 0:
        return False, f"Checkov exited with code {returncode}."
    if _DOWNLOAD_FAILURE in stderr.lower():
        return False, "Checkov could not download one or more external modules."
    if not stdout.strip():
        return False, "Checkov returned empty output."

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError as exc:
        return False, f"Checkov returned invalid JSON: {exc}."

    envelopes = payload if isinstance(payload, list) else [payload]
    if not envelopes or not all(isinstance(item, dict) for item in envelopes):
        return False, "Checkov returned an unexpected JSON envelope."

    passed = failed = skipped = parsing_errors = failed_check_details = 0
    for envelope in envelopes:
        summary = envelope.get("summary")
        results = envelope.get("results")
        if not isinstance(summary, dict) or not isinstance(results, dict):
            return False, "Checkov JSON is missing summary or results."

        required_counts = ("passed", "failed", "skipped", "parsing_errors")
        if not all(key in summary for key in required_counts):
            return False, "Checkov summary is missing a required result count."
        try:
            passed += int(summary["passed"])
            failed += int(summary["failed"])
            skipped += int(summary["skipped"])
            parsing_errors += int(summary["parsing_errors"])
        except (TypeError, ValueError):
            return False, "Checkov summary counts are not numeric."

        failed_checks = results.get("failed_checks")
        if not isinstance(failed_checks, list):
            return False, "Checkov JSON has an invalid failed_checks field."
        failed_check_details += len(failed_checks)

    summary_text = (
        f"passed={passed} failed={failed} skipped={skipped} "
        f"parsing_errors={parsing_errors}"
    )
    if failed or failed_check_details:
        return False, f"Checkov reported failed checks ({summary_text})."
    if parsing_errors:
        return False, f"Checkov reported parsing errors ({summary_text})."
    return True, f"Checkov passed ({summary_text})."


def _checkov_command() -> list[str]:
    sibling = pathlib.Path(sys.executable).with_name("checkov")
    if sibling.is_file():
        return [sys.executable, str(sibling)]
    return ["checkov"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", required=True)
    parser.add_argument("--external-modules-download-path")
    args = parser.parse_args(argv)

    command = [
        *_checkov_command(),
        "--directory",
        args.directory,
        "--framework",
        "terraform",
        "--download-external-modules",
        "true",
        "--output",
        "json",
        "--quiet",
    ]
    if args.external_modules_download_path:
        command.extend(
            ["--external-modules-download-path", args.external_modules_download_path]
        )

    try:
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
    except OSError as exc:
        print(f"Checkov could not start: {exc}", file=sys.stderr)
        return 1

    passed, message = assess_result(
        completed.returncode,
        completed.stdout,
        completed.stderr,
    )
    stream: Any = sys.stdout if passed else sys.stderr
    print(message, file=stream)
    if not passed and completed.stderr.strip():
        print(completed.stderr.strip(), file=sys.stderr)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
