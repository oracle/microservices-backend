# Copyright (c) 2026, Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v1.0 as shown at https://oss.oracle.com/licenses/upl

import importlib.util
from pathlib import Path
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "runner", Path(__file__).with_name("run-mocked-plans.py")
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

LABEL_FIXTURE = '''
run "persist_generated_label" {
  command = apply
  plan_options {
    target = [random_pet.label]
  }
}
'''


class SuiteSafetyTests(unittest.TestCase):
    def check(self, content):
        with tempfile.TemporaryDirectory() as directory:
            suite = Path(directory) / "fixture.tftest.hcl"
            suite.write_text(content)
            runner.check_suite(suite)

    def test_local_random_fixture_is_allowed(self):
        self.check('mock_provider "oci" {}\nprovider "random" {}\n' + LABEL_FIXTURE)

    def test_real_oci_provider_is_rejected_with_local_fixture(self):
        with self.assertRaisesRegex(ValueError, "real random provider"):
            self.check('mock_provider "tls" {}\nprovider "oci" {}\n' + LABEL_FIXTURE)

    def test_real_random_provider_requires_targeted_fixture(self):
        with self.assertRaisesRegex(ValueError, "real random provider"):
            self.check('''mock_provider "oci" {}
provider "random" {}
run "plan" {
  command = plan
}
''')

    def test_local_fixture_cannot_apply_other_resources(self):
        with self.assertRaisesRegex(ValueError, "targeted fixture"):
            self.check(
                'mock_provider "oci" {}\n'
                + LABEL_FIXTURE.replace("random_pet.label", "oci_core_vcn.default")
            )


if __name__ == "__main__":
    unittest.main()
