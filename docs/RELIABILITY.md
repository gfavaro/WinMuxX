# Reliability and configuration safeguards

## Native apps and automation

Failed Accessibility registration is shared by callers and retried after 1, 2, 4,
8 and 16 seconds. After those five automatic retries, incidental attempts back off
for 30 seconds. Process-launch identity prevents a reused PID inheriting an old
process's retry state. App termination, disabling tiling and shutdown cancel pending
retry work. There is no permanent polling timer for failed registration.

An actual AX `cannotComplete` result stops further native reads/writes to that app
within the same refresh budget. Other apps and the next refresh retain independent
budgets. Queue hops preserve that budget, so already queued reads cannot each wait
out the timeout. Elapsed time is not used to guess whether a request timed out.
Focused-window requests retain their 250 ms timeout; general requests retain 1 s.
An unanswered focus or fullscreen/minimize read is unknown, not evidence that a
window vanished or changed state.

Normalization validates observations before acting, respects explicit workspace
moves made during a read, and preserves focus ordering during native bookkeeping.
Window detection owns its committed rule task: cancelling a background refresh does
not cut its command list in half. Window destruction, app termination or shutdown
can still cancel it. Apparent popups receive two bounded rechecks without needing a
click. Failed commands are not silently replayed.

## Monitor UUIDs

Get stable display identifiers with:

```sh
winmuxx list-monitors --format '%{monitor-name} | %{monitor-uuid}'
```

Existing monitor arguments accept `uuid:<UUID>`, for example:

```sh
winmuxx focus-monitor 'uuid:AAAAAAAA-0000-4000-8000-000000000001'
winmuxx move-workspace-to-monitor --workspace 5 'uuid:AAAAAAAA-0000-4000-8000-000000000002'
```

Replace the sample UUID with the value printed on your machine. `--workspace`
takes the internal workspace name reported by `list-workspaces`; automatic sidebar
numbers can differ. UUIDs are case-insensitive; malformed UUID selectors are errors,
and a disconnected or ambiguous UUID never silently selects a different display.
The same selector strings work in existing per-monitor config values and assignment
lists. Existing main/secondary/index/name selectors retain their behavior. UUID
support does not enable automatic workspace relocation or change startup defaults.

## Config and saved state

Settings, shortcut and sidebar edits share a synchronous MainActor write boundary.
Structured edits operate on fresh disk text, preserve unrelated content, and validate
the exact resulting config before writing. Raw editor drafts retain the disk baseline
they were edited against, including when Settings is reopened; a stale save is refused
with a reload/retry message. No-op saves do not rewrite the file or rotate backups.

Changed configs keep the previous five versions beside the actual target as
`<config>.backup.1` through `.backup.5`, newest first. Symlinks remain symlinks;
replacement and backup files are created with owner-only `0600` permissions before
an atomic rename. Filesystem and validation failures are reported through the
existing save UI. Bootstrap imports use the same private atomic primitive; legacy
imports preserve their bytes and are checked for TOML syntax, while generated and
migrated configs receive full semantic validation.

All writers inside WinMuxX are serialized without suspension. External changes are
checked before committing, including after backup I/O; structured edits are retried
against fresh content, and stale raw replacements are rejected. This is detection,
not an operating-system compare-and-swap: a noncooperating external process can still
race the final check and rename. Keeping backup history provides recovery.

Restart state and its backup also use `0600`, including existing files encountered
on load. Their schema, tree/ratio restoration, ambiguity checks and monitor ownership
rules are unchanged.

## Shutdown, IPC and diagnostics

SIGINT/SIGTERM delivery runs off MainActor. Existing cleanup gets ten seconds; if
MainActor or cleanup cannot finish, the process exits anyway and logs the deadline.
Forced termination cannot guarantee that hidden windows were restored.

CLI IPC keeps Network.framework and its native-endian wire format. Frames are capped
at 16 MiB before allocation. Truncated frames and EOF terminate reads; cancellation
closes pending receives. The server allows 30 seconds to receive a complete command
frame. This is not an execution deadline, and established event subscriptions have
no idle deadline.

Tree detach operations no longer symbolize stacks routinely. Launch with
`WINMUXX_TRACE_TREE_BINDINGS=1` when investigating double-unbind failures; normal
operation leaves this tracing off in both Debug and Release builds.
