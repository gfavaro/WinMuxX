# Dependencies and toolchain

Reviewed against the production call sites on 2026-10-16. Package.swift and
Package.resolved are the authoritative requirements and resolved revisions.
This is a usage and simplification audit, not a vulnerability or latest-version
certification. Existing dependency versions were not upgraded.

| External package | Pin | Decision |
| --- | --- | --- |
| HotKey | 0.2.1 | Keep: runtime hotkey registration, key codes and keyboard-layout mapping. |
| MASShortcut | 2f9fbb3f959b7a683c6faaf9638d22afad37a235 | Keep: native shortcut recorder and validation in Settings; a different responsibility from runtime registration. |
| TOMLKit | 0.5.5 | Keep: configuration decoding, validation and structured settings writes. |
| swift-collections | 1.3.0 | Keep: ordered workspace configuration and ordered diagnostic records; replacing these needs equivalent ordering and uniqueness guarantees. |
| Sparkle | 2.9.6 | Keep: isolated automatic-update integration. Personal fork releases continue to disable updates. |

ISSoundAdditions 2.0.1 was removed. Volume commands now use a small CoreAudio
boundary with the same virtual-main-volume property, 1/16 steps, clamping,
0.005 automatic-mute threshold, best-effort failure behavior and existing panel.
Mute writes use CoreAudio's UInt32 property size. Tests exercise command policy
without changing the machine's audio. Real output-device compatibility remains
a separate runtime check.

ANTLR 4.13.1 was removed from the app dependency graph in build 72. A fresh
index and whole-repository call-site review then confirmed the unfinished shell
parser was unreachable. Its experimental source, commented-out tests, generated
standalone package and unused ANTLR installer support were removed in the Settings
cleanup. Existing command tokenization and Bash execution are unchanged.

The app has five external packages, all pinned. Apple frameworks and the local
PrivateApi C/Objective-C target are not third-party packages. Network.framework
Unix-socket IPC remains: changing transport would add work without a demonstrated
reliability or performance benefit.

## Swift

The repository and CI pin is Swift 6.4.0, matching the locally installed Apple
Swift 6.4 release version. Package tools minimum remains 6.2. These version checks
align release numbers, not Apple and Swift.org compiler build identifiers or SDKs.
Xcode/SDK versions are recorded separately in CI.

`script/setup.sh` checks the selected compiler and fails on a version mismatch.
Swiftly, when installed, selects the repository pin; otherwise the active compiler
must match. `script/fork-build.sh` explicitly passes that compiler to Xcode through
SWIFT_EXEC, ensuring the release app and CLI use the same compiler executable.
CI installs the pin from `.swift-version`; remote CI validation is separate from
local verification.

`make check` uses SwiftPM's forced resolved versions, rejecting an out-of-date
lockfile before tests instead of silently resolving changes. Deliberate dependency
edits require `swift package resolve` and review of Package.resolved.
