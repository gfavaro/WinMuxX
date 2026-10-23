# Dinky adaptations execution results

Started 2026-10-22. Baseline `44fe40fd1a0e7216868a1f9aef8dd8c818eb48fa`.
Initial working tree contained the two Dinky review documents and index/roadmap
links from the evaluation. Swift 6.4 is required by `script/setup.sh`.

| Task | Status | Evidence |
| --- | --- | --- |
| P0 | done | Existing tests and source paths inventoried; baseline captured above. |
| D1–D4 | done | Added quick start, concepts, layouts with SVGs, recipes and task-based commands. README/docs navigation and Unreleased changelog added; 0.20 historical command context clarified. Four parser-backed recipe examples pass. All five SVGs rendered and visually inspected at 360px and 1,000px. |
| S1 | done | Added parser-backed field inventory in `CONFIGURATION_SCHEMA_INVENTORY.md`. |
| S2 | done | Draft 2020-12 schema validates with pinned `jsonschema==4.23.0`; 11 shared fixtures have parser/schema expectations; Swift and Python checks pass; static parser-key coverage includes all 47 root keys. Runtime-only command semantics remain intentionally parser-owned. |
| S3 | implemented; editor check pending | Added pinned validator setup and an Even Better TOML VS Code association with completion/error examples. `code` is not installed in this environment, so editor UI feedback could not be exercised. |
| H1–H3 | partial | Side-filtered event tap availability state, bounded recovery, menu warning and doctor line are implemented. Four injected retry policy tests and menu/doctor tests pass. Carbon registration health is not exposed by the current hotkey backend; native permission and VoiceOver review remain. |
| R1 | done | Reproduced dangling symlink replacement; bootstrap now resolves the symlink destination. Regression passes. |
| R2 | pending | Existing tests cover drag sample coalescing/velocity and resize calibration, but not a layout mutation during a live drag. The current tests have no model seam for changing layout while preserving a pointer drag; native reproduction remains pending. |
| R3 | partial | Added an 11-sibling resize regression; it passes and confirms positive finite weights and retained tree membership. Native visual check remains. |
| R4 | done | Reproduced mixed quote and leading combining mark loss; Unicode-scalar parser and quote/backslash round-trip now pass. |
| R5 | partial | Existing monitor navigation tests remain; no physical topology checks performed. |
| V1 | implemented; manual checks pending | `make check` passed 1,354 Swift tests and all Python checks, including the new retry and schema fixtures. Native, editor and remote CI checks remain. |

Checks run: `winmuxx --help` from the local debug binary printed the command
inventory. Focused parser/example, argument, symlink, crowded resize, menu /
diagnostics, four retry-policy cases, and shared schema-fixture tests passed.
The JSON Schema validates against Draft 2020-12 and its static root keys cover
all 47 root parser keys. `make check` passed 1,354 Swift tests and all Python
checks. The native border-surface eligibility regression passed; signed build
131 installed and launched with the prior workspace assignments and focus
restored, and no windows opened, closed, or moved. `git diff --check` passed.
Live drag/layout, physical display, editor UI, VoiceOver and remote CI validation
remain pending; the app build is not a release or notarized distribution.
