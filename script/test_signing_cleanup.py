"""Signing cleanup tests use fake commands, never the developer's keychains."""
import contextlib
import io
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from script.cleanup_signing_identity import cleanup

SCRIPT = pathlib.Path(__file__).resolve().with_name("cleanup_signing_identity.py")


class SigningCleanupTests(unittest.TestCase):
    def run_cleanup(self, *, deletion="success", present=True, partial=False, hosted=True):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            commands = root / "bin"
            commands.mkdir()
            security = commands / "security"
            security.write_text('''#!/usr/bin/env python3
import os, pathlib, sys, time
with open(os.environ['COMMAND_LOG'], 'a') as log:
    log.write(' '.join(sys.argv[1:]) + '\\n')
if sys.argv[1] != 'delete-keychain': sys.exit(99)
if os.environ['DELETE_RESULT'] == 'hang': time.sleep(10)
if os.environ['DELETE_RESULT'] == 'denied':
    print('Authorization was denied.', file=sys.stderr)
    sys.exit(1)
pathlib.Path(sys.argv[2]).unlink(missing_ok=True)
''')
            security.chmod(0o755)
            names = ["winmuxx-signing.cer", "winmuxx-signing.p12"]
            if not partial:
                names += ["winmuxx-signing.keychain-db", "winmuxx-signing.keychain-db-wal",
                          "winmuxx-signing.keychain-db-shm"]
            if present:
                for name in names:
                    (root / name).write_text("synthetic fixture")
            log = root / "commands.log"
            environment = {**os.environ, "RUNNER_TEMP": str(root),
                           "RUNNER_ENVIRONMENT": "github-hosted" if hosted else "self-hosted",
                           "PATH": str(commands) + os.pathsep + os.environ["PATH"],
                           "COMMAND_LOG": str(log), "DELETE_RESULT": deletion}
            command = [sys.executable, str(SCRIPT), "--command-timeout", "0.2" if deletion == "hang" else "2"]
            first = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=5)
            calls = log.read_text().splitlines() if log.exists() else []
            remaining = [name for name in names if (root / name).exists()]
            second = subprocess.run(command, env=environment, capture_output=True, text=True, timeout=5)
            return first, calls, remaining, second

    def test_completed_import_and_repeated_cleanup(self):
        first, calls, remaining, second = self.run_cleanup()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertEqual(len(calls), 1)
        self.assertTrue(calls[0].startswith("delete-keychain "))
        self.assertEqual(second.returncode, 0, second.stderr)

    def test_interrupted_import_removes_certificate_and_archive_without_trust_commands(self):
        first, calls, remaining, _ = self.run_cleanup(partial=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertEqual(calls, [])

    def test_keychain_api_failure_falls_back_to_removing_private_files(self):
        first, _, remaining, _ = self.run_cleanup(deletion="denied")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertIn("::warning::", first.stdout)

    def test_hung_keychain_api_is_bounded_and_private_files_are_removed(self):
        first, _, remaining, _ = self.run_cleanup(deletion="hang")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(remaining, [])
        self.assertIn("::warning::", first.stdout)

    def test_no_import_does_not_call_security(self):
        first, calls, remaining, second = self.run_cleanup(present=False)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(remaining, [])
        self.assertEqual(second.returncode, 0)

    def test_refuses_persistent_or_local_runners_without_touching_files(self):
        first, calls, remaining, _ = self.run_cleanup(hosted=False)
        self.assertNotEqual(first.returncode, 0)
        self.assertEqual(calls, [])
        self.assertEqual(len(remaining), 5)

    def test_failure_to_remove_files_is_not_silenced(self):
        with patch("pathlib.Path.exists", return_value=False), \
             patch("pathlib.Path.unlink", side_effect=PermissionError("fixture denied")), \
             contextlib.redirect_stderr(io.StringIO()):
            self.assertNotEqual(cleanup(pathlib.Path("/synthetic-not-touched")), 0)


if __name__ == "__main__":
    unittest.main()
