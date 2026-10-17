"""Run signing cleanup against fake commands, never the developer's keychains."""
import os
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().with_name("cleanup-signing-identity.sh")


class SigningCleanupTests(unittest.TestCase):
    def run_cleanup(self, *, trust="success", deletion="success", present=True):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            commands = root / "bin"
            commands.mkdir()
            security = commands / "security"
            security.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$COMMAND_LOG"
case "$1" in
  remove-trusted-cert) outcome="$TRUST_RESULT" ;;
  delete-keychain) outcome="$DELETE_RESULT" ;;
  *) exit 99 ;;
esac
case "$outcome" in
  missing) echo 'The specified item could not be found in the keychain.' >&2; exit 1 ;;
  denied) echo 'Authorization was denied.' >&2; exit 1 ;;
esac
if [[ "$1" == delete-keychain ]]; then rm -f "$2"; fi
''')
            security.chmod(0o755)
            sudo = commands / "sudo"
            sudo.write_text('#!/bin/bash\n[[ "$1" == -n ]] || exit 99\nshift\nexec "$@"\n')
            sudo.chmod(0o755)
            names = ["winmuxx-signing.cer", "winmuxx-signing.keychain-db", "winmuxx-signing.p12"]
            if present:
                for name in names:
                    (root / name).write_text("synthetic fixture")
            log = root / "commands.log"
            environment = {**os.environ, "RUNNER_TEMP": str(root),
                           "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                           "COMMAND_LOG": str(log), "TRUST_RESULT": trust, "DELETE_RESULT": deletion}
            first = subprocess.run(["bash", str(SCRIPT)], env=environment, capture_output=True, text=True, timeout=5)
            calls = log.read_text().splitlines() if log.exists() else []
            remaining = [name for name in names if (root / name).exists()]
            second = subprocess.run(["bash", str(SCRIPT)], env=environment, capture_output=True, text=True, timeout=5)
            return first, calls, remaining, second

    def test_completed_import_is_cleaned_and_repeated_cleanup_is_harmless(self):
        first, calls, remaining, second = self.run_cleanup()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[0].startswith("remove-trusted-cert -d "))
        self.assertTrue(calls[1].startswith("delete-keychain "))
        self.assertEqual(second.returncode, 0, second.stderr)

    def test_missing_trust_after_interrupted_import_still_deletes_keychain(self):
        first, calls, remaining, _ = self.run_cleanup(trust="missing")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertEqual(len(calls), 2)

    def test_unexpected_trust_error_does_not_skip_private_key_cleanup(self):
        first, calls, remaining, _ = self.run_cleanup(trust="denied")
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual(remaining, [])
        self.assertEqual(len(calls), 2)
        self.assertIn("Authorization was denied", first.stderr)

    def test_keychain_failure_is_reported_but_certificate_and_archive_are_removed(self):
        first, _, remaining, _ = self.run_cleanup(deletion="denied")
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual(remaining, ["winmuxx-signing.keychain-db"])

    def test_no_import_does_not_call_security(self):
        first, calls, remaining, second = self.run_cleanup(present=False)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(remaining, [])
        self.assertEqual(second.returncode, 0)


if __name__ == "__main__":
    unittest.main()
