from __future__ import annotations

import importlib.util
import json
import pathlib
import tempfile
import unittest

_SCRIPT = pathlib.Path(__file__).with_name("checkov_fail_closed.py")
_SPEC = importlib.util.spec_from_file_location("checkov_fail_closed", _SCRIPT)
assert _SPEC and _SPEC.loader
_MODULE = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_MODULE)
assess_result = _MODULE.assess_result
authored_terraform_files = _MODULE.authored_terraform_files


def _payload(*, failed_checks=None, parsing_errors=None):
    failed_checks = failed_checks or []
    parsing_errors = parsing_errors or []
    return json.dumps(
        {
            "check_type": "terraform",
            "results": {
                "passed_checks": [{}],
                "failed_checks": failed_checks,
                "skipped_checks": [],
                "parsing_errors": parsing_errors,
            },
            "summary": {
                "passed": 1,
                "failed": len(failed_checks),
                "skipped": 0,
                "parsing_errors": len(parsing_errors),
            },
        }
    )


def _summary_only(*, failed=0, parsing_errors=0):
    return json.dumps(
        {
            "passed": 0,
            "failed": failed,
            "skipped": 0,
            "parsing_errors": parsing_errors,
            "resource_count": 0,
        }
    )


class AssessResultTests(unittest.TestCase):
    def test_valid_clean_envelope_passes(self):
        passed, message = assess_result(0, _payload(), "")
        self.assertTrue(passed)
        self.assertIn("parsing_errors=0", message)

    def test_valid_summary_only_envelope_passes(self):
        passed, message = assess_result(0, _summary_only(), "")
        self.assertTrue(passed)
        self.assertIn("failed=0", message)

    def test_failed_check_blocks(self):
        passed, _ = assess_result(0, _payload(failed_checks=[{"check_id": "X"}]), "")
        self.assertFalse(passed)

    def test_parsing_error_blocks_even_when_process_exits_zero(self):
        passed, _ = assess_result(0, _payload(parsing_errors=["bad.tf:1"]), "")
        self.assertFalse(passed)

    def test_failed_module_download_blocks(self):
        passed, _ = assess_result(0, _payload(), "Failed to download module example")
        self.assertFalse(passed)

    def test_nonzero_exit_blocks(self):
        passed, _ = assess_result(2, _payload(), "")
        self.assertFalse(passed)

    def test_empty_output_blocks(self):
        passed, _ = assess_result(0, "", "")
        self.assertFalse(passed)

    def test_malformed_json_blocks(self):
        passed, _ = assess_result(0, "not json", "")
        self.assertFalse(passed)

    def test_missing_result_schema_blocks(self):
        passed, _ = assess_result(0, json.dumps({"summary": {}}), "")
        self.assertFalse(passed)

    def test_missing_parsing_error_count_blocks(self):
        payload = json.loads(_payload())
        del payload["summary"]["parsing_errors"]
        passed, _ = assess_result(0, json.dumps(payload), "")
        self.assertFalse(passed)


class AuthoredTerraformFilesTests(unittest.TestCase):
    def test_returns_only_repository_authored_tf_files(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = pathlib.Path(temp_dir)
            (root / "main.tf").write_text("terraform {}", encoding="utf-8")
            (root / "modules").mkdir()
            (root / "modules" / "child.tf").write_text("terraform {}", encoding="utf-8")
            (root / ".terraform" / "modules").mkdir(parents=True)
            (root / ".terraform" / "modules" / "downloaded.tf").write_text(
                "terraform {}", encoding="utf-8"
            )
            (root / ".external_modules").mkdir()
            (root / ".external_modules" / "downloaded.tf").write_text(
                "terraform {}", encoding="utf-8"
            )

            relative_paths = [
                path.relative_to(root).as_posix()
                for path in authored_terraform_files(root)
            ]

            self.assertEqual(relative_paths, ["main.tf", "modules/child.tf"])


if __name__ == "__main__":
    unittest.main()
