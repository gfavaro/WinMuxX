#!/usr/bin/env python3
"""Check maintained contributor guides without third-party Python dependencies.

Checks inline local file links (not anchors), explicit Sources/ paths in backticks,
and backticked XCTest class/method names. Not a general Markdown or web validator.
"""

from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parent.parent
GUIDES = (
    "AGENTS.md", "CONTRIBUTING.md", "HACKING.md", "README.md", "docs/README.md",
    ".github/PULL_REQUEST_TEMPLATE.md",
    "docs/PRINCIPLES.md", "docs/TESTING.md", "docs/CONTRIBUTOR_TASKS.md",
    "docs/WORKSPACE_BEHAVIOR.md", "docs/AGENT_EVALUATION.md",
    ".agents/skills/winmuxx-workspaces/SKILL.md",
)


def check(root, guides=GUIDES):
    errors = []
    test_sources = list((root / "Sources/AppBundleTests").rglob("*.swift"))
    symbols = set()
    for path in test_sources:
        symbols.update(re.findall(r"\b(?:class|func)\s+(\w+)", path.read_text()))
    for name in guides:
        path = root / name
        if not path.is_file():
            errors.append(f"{name}: guide missing")
            continue
        source = path.read_text()
        for target in re.findall(r"\[[^\]\n]*\]\(([^\s)]+)\)", source):
            parsed = urlsplit(target)
            if parsed.scheme or parsed.netloc or not parsed.path:
                continue
            if not (path.parent / unquote(parsed.path)).exists():
                errors.append(f"{name}: missing local link {target}")
        for value in re.findall(r"`([^`\n]+)`", source):
            if value.startswith("Sources/") and " " not in value:
                if not (root / value).exists():
                    errors.append(f"{name}: missing source path {value}")
            if re.fullmatch(r"(?:[A-Z]\w*Test|test[A-Z]\w*)", value):
                if value not in symbols:
                    errors.append(f"{name}: missing XCTest symbol {value}")
    return errors


if __name__ == "__main__":
    problems = check(ROOT)
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    print(f"Contributor guidance: {len(GUIDES)} files checked; local links, source paths and XCTest symbols resolve.")
