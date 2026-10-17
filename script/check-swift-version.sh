#!/bin/bash
set -euo pipefail
expected_swift_version="$(tr -d '[:space:]' < "$(dirname "$0")/../.swift-version")"
actual_swift_version="$(printf '%s\n' "$1" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+(\.[0-9]+)?)([[:space:]]|$).*/\1/p')"
# Apple omits a zero patch component in its compiler version string.
if [[ "$actual_swift_version" != "$expected_swift_version" && "$actual_swift_version.0" != "$expected_swift_version" ]]; then
    echo "Swift $expected_swift_version required; found ${actual_swift_version:-unknown}. Install the pinned version with swiftly install, or select matching Xcode with DEVELOPER_DIR." >&2
    exit 1
fi
