import pathlib
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parent.parent


class SwiftVersionTest(unittest.TestCase):
    def check_version(self, description):
        return subprocess.run(
            [str(ROOT / "script/check-swift-version.sh"), description],
            cwd="/tmp", capture_output=True, text=True, check=False,
        )

    def test_accepts_pinned_release_and_apple_zero_patch_omission(self):
        version = (ROOT / ".swift-version").read_text().strip()
        for displayed in {version, version.removesuffix(".0")}:
            with self.subTest(displayed=displayed):
                result = self.check_version(f"Apple Swift version {displayed} (swiftlang-build)")
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_mismatched_patch_minor_and_unrecognized_output(self):
        version = (ROOT / ".swift-version").read_text().strip()
        major, minor, patch = map(int, version.split("."))
        for displayed in [f"{major}.{minor}.{patch + 1}", f"{major}.{minor + 1}.0", f"{version}-dev", "unknown"]:
            with self.subTest(displayed=displayed):
                result = self.check_version(f"Swift version {displayed}")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Swift {version} required", result.stderr)
