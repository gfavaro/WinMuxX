import tempfile
import unittest
from pathlib import Path

from script.check_contributor_guidance import check


class ContributorGuidanceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        tests = self.root / "Sources/AppBundleTests"
        tests.mkdir(parents=True)
        (tests / "ExampleTest.swift").write_text(
            "class ExampleTest { func testMovingPreservesTabs() {} }"
        )
        (self.root / "docs").mkdir()
        (self.root / "docs/Other Guide.md").write_text("# Other guide")

    def run_check(self, text):
        (self.root / "docs/Guide.md").write_text(text)
        return check(self.root, ("docs/Guide.md",))

    def test_resolves_relative_encoded_links_and_symbols_without_network(self):
        self.assertEqual(self.run_check(
            "[Other](Other%20Guide.md#section) [web](https://example.invalid/no-file) "
            "[heading](#local) `Sources/AppBundleTests/ExampleTest.swift` "
            "`ExampleTest` `testMovingPreservesTabs`"
        ), [])

    def test_reports_stale_link_source_and_test(self):
        errors = self.run_check(
            "[missing](missing.md) `Sources/missing.swift` `testMissingBehavior`"
        )
        self.assertEqual(len(errors), 3)
        self.assertTrue(any("missing local link" in error for error in errors))
        self.assertTrue(any("missing source path" in error for error in errors))
        self.assertTrue(any("missing XCTest symbol" in error for error in errors))

    def test_missing_guide_fails_instead_of_silently_skipping(self):
        self.assertEqual(check(self.root, ("absent.md",)), ["absent.md: guide missing"])


if __name__ == "__main__":
    unittest.main()
