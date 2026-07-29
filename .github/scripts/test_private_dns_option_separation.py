from __future__ import annotations

import pathlib
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
PARENT = REPO_ROOT / "examples" / "cross-tenant-private-link-dns"
STANDARD = PARENT / "standard-contexts"
PREFIXED = PARENT / "prefixed-backing"
REQUIRED_FILES = {
    ".terraform.lock.hcl",
    "README.md",
    "cross_tenant_private_endpoints.tf",
    "dns_resolver.tf",
    "private_dns_zones.tf",
    "terraform.tfvars.example",
    "tests/validation.tftest.hcl",
    "z_locals.tf",
    "z_outputs.tf",
    "z_variables.tf",
    "z_versions.tf",
}


def relative_files(root: pathlib.Path) -> set[str]:
    return {
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and ".terraform" not in path.parts
    }


def authored_hcl(root: pathlib.Path) -> str:
    paths = sorted(root.glob("*.tf")) + [root / "terraform.tfvars.example"]
    return "\n".join(path.read_text(encoding="utf-8") for path in paths)


class PrivateDnsOptionSeparationTests(unittest.TestCase):
    def test_parent_is_catalog_only(self):
        self.assertEqual(list(PARENT.glob("*.tf")), [])
        self.assertFalse((PARENT / ".terraform.lock.hcl").exists())
        self.assertFalse((PARENT / "terraform.tfvars.example").exists())

    def test_each_option_is_a_complete_root(self):
        for option in (STANDARD, PREFIXED):
            with self.subTest(option=option.name):
                self.assertTrue(REQUIRED_FILES.issubset(relative_files(option)))
                self.assertNotIn("../", authored_hcl(option))

    def test_standard_option_has_no_prefixed_mode_inputs(self):
        text = authored_hcl(STANDARD)
        for forbidden in (
            "dns_architecture",
            "prefixed_private_dns_zones",
            "publish_dns_records",
            "approved_private_endpoint_target_keys",
            "dns_family",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, text)

    def test_prefixed_option_has_no_standard_mode_composition(self):
        text = authored_hcl(PREFIXED)
        for forbidden in (
            "dns_architecture",
            "existing_private_dns_zone_ids",
            "standard_private_dns_zones",
            "private_dns_zone_group",
        ):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, text)

    def test_catalog_and_ci_name_both_options(self):
        catalog = (PARENT / "README.md").read_text(encoding="utf-8")
        workflow = (
            REPO_ROOT / ".github" / "workflows" / "terraform-validate.yml"
        ).read_text(encoding="utf-8")
        for option in ("standard-contexts", "prefixed-backing"):
            with self.subTest(option=option):
                self.assertIn(f"{option}/", catalog)
                self.assertIn(f"- {option}", workflow)


if __name__ == "__main__":
    unittest.main()
