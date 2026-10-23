#!/usr/bin/env python3
"""Validate shared TOML fixtures against the editor schema and parser inventory."""

import json
import re
import sys
from pathlib import Path

try:
    import tomli
    from jsonschema import Draft202012Validator
except ImportError as error:
    raise SystemExit(
        "Config schema checks need the pinned dependencies. Run "
        "python3 -m venv .deps/config-schema && "
        ".deps/config-schema/bin/pip install -r requirements-schema.txt"
    ) from error


ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "docs/schemas/winmuxx.schema.json"
FIXTURES = ROOT / "resources/test-fixtures/config-schema"


def main():
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    expectations = json.loads((FIXTURES / "expectations.json").read_text(encoding="utf-8"))
    fixture_names = {path.name for path in FIXTURES.glob("*.toml")}
    if fixture_names != set(expectations):
        raise AssertionError(
            f"Fixture manifest mismatch; unlisted={sorted(fixture_names - set(expectations))}, "
            f"missing={sorted(set(expectations) - fixture_names)}"
        )

    for name, expected in sorted(expectations.items()):
        document = tomli.loads((FIXTURES / name).read_text(encoding="utf-8"))
        errors = list(validator.iter_errors(document))
        actual = not errors
        if actual != expected["schema"]:
            detail = "; ".join("/".join(map(str, error.absolute_path)) + ": " + error.message for error in errors)
            raise AssertionError(f"{name}: schema expected {expected['schema']}, got {actual}: {detail}")

    parser_source = (ROOT / "Sources/AppBundle/config/parseConfig.swift").read_text(encoding="utf-8")
    static_keys = set(re.findall(r'^\s*"([^"\n]+)"\s*:\s*Parser\(', parser_source, re.MULTILINE))
    static_keys.update(re.findall(r'^private let \w+ = "([^"\n]+)"', parser_source, re.MULTILINE))
    schema_keys = set(schema["properties"])
    uncovered = static_keys - schema_keys
    if uncovered:
        raise AssertionError(f"Static parser keys missing from schema: {', '.join(sorted(uncovered))}")
    print(f"Validated schema and {len(expectations)} shared fixtures; covered {len(static_keys)} static parser keys.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # Report a concise check failure to make in make check logs.
        print(f"config schema check failed: {error}", file=sys.stderr)
        raise
