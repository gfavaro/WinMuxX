#!/usr/bin/env python3
"""Fail when a Swift source file grows past its size cap, so a file is split before it sprawls."""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE_CAP = 800
TEST_CAP = 1000


def main() -> int:
    failures = []
    for path in sorted((ROOT / "Sources").rglob("*.swift")):
        relative = path.relative_to(ROOT)
        cap = TEST_CAP if "Tests" in relative.parts[1] else SOURCE_CAP
        lines = sum(1 for _ in path.open(encoding="utf-8", errors="ignore"))
        if lines > cap:
            failures.append(f"{relative}: {lines} lines (limit {cap})")
    if failures:
        print("Split these files:\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
