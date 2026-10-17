#!/usr/bin/env python3
"""Delete temporary signing material on disposable GitHub-hosted macOS runners.

Do not call remove-trusted-cert: it can hang even under sudo (runner-images#12116).
Deleting our temporary keychain removes the certificate and private key; the VM's
admin trust metadata disappears when GitHub decommissions that runner.
"""
import argparse
import os
from pathlib import Path
import subprocess
import sys


def cleanup(root: Path, command_timeout: float = 30) -> int:
    keychain = root / "winmuxx-signing.keychain-db"
    if keychain.exists():
        print("Deleting temporary signing keychain (bounded command).", flush=True)
        try:
            result = subprocess.run(["security", "delete-keychain", str(keychain)],
                                    capture_output=True, text=True, timeout=command_timeout)
            if result.returncode:
                print(f"::warning::Keychain API cleanup failed; removing temporary files: {result.stderr.strip()}", flush=True)
        except (subprocess.TimeoutExpired, OSError) as error:
            print(f"::warning::Keychain API cleanup unavailable; removing temporary files: {error}", flush=True)

    # Also handles interrupted imports and SQLite sidecars. Never touch login/system
    # keychains. A stale search-list entry on this disposable VM contains no key data.
    failed = False
    for name in ["winmuxx-signing.keychain-db", "winmuxx-signing.keychain-db-wal",
                 "winmuxx-signing.keychain-db-shm", "winmuxx-signing.cer", "winmuxx-signing.p12"]:
        try:
            (root / name).unlink(missing_ok=True)
        except OSError as error:
            print(f"::error::Unable to remove temporary signing file {name}: {error}", file=sys.stderr)
            failed = True
    if not failed:
        print("Temporary signing files removed.", flush=True)
    return int(failed)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command-timeout", type=float, default=30)
    args = parser.parse_args()
    if not 0 < args.command_timeout <= 30:
        parser.error("command timeout must be greater than zero and at most 30 seconds")
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        parser.error("this cleanup is only for disposable GitHub-hosted runners")
    return cleanup(Path(os.environ["RUNNER_TEMP"]), args.command_timeout)


if __name__ == "__main__":
    sys.exit(main())
